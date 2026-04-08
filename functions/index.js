const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const crypto = require("crypto");
const ExcelJS = require("exceljs");

admin.initializeApp();
const db = admin.firestore();

function generateCode(length) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.randomBytes(length);
  let result = "";
  for (let i = 0; i < length; i += 1) {
    result += alphabet[bytes[i] % alphabet.length];
  }
  return result;
}

function hashCode(code) {
  return crypto.createHash("sha256").update(code).digest("hex");
}

async function getUserRole(uid) {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists) return null;
  const data = doc.data() || {};
  return data.role || null;
}

async function getAuthUid(request) {
  if (request.auth && request.auth.uid) {
    return request.auth.uid;
  }

  const idToken = request.data && request.data.idToken
    ? request.data.idToken.toString()
    : "";
  if (!idToken) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    return decoded.uid;
  } catch (err) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
}

async function requireSuperAdmin(request) {
  const uid = await getAuthUid(request);
  const role = await getUserRole(uid);
  if (role !== "super_admin" && role !== "superadmin") {
    throw new HttpsError("permission-denied", "Super admin access required.");
  }
  return uid;
}

async function requireAdminOrSuper(request) {
  const uid = await getAuthUid(request);
  const role = await getUserRole(uid);
  if (role !== "super_admin" && role !== "admin") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  return { uid, role };
}

async function requireRecentReauth(request, maxAgeSeconds = 300) {
  const requestUid = request.auth && request.auth.uid
    ? request.auth.uid
    : "";
  const requestAuthTimeSec = Number(
    request.auth && request.auth.token && request.auth.token.auth_time
      ? request.auth.token.auth_time
      : 0
  );

  const idToken = request.data && request.data.idToken
    ? request.data.idToken.toString()
    : "";

  let tokenUid = "";
  let tokenAuthTimeSec = 0;
  if (idToken) {
    try {
      const decoded = await admin.auth().verifyIdToken(idToken, true);
      tokenUid = decoded.uid || "";
      tokenAuthTimeSec = Number(decoded.auth_time || 0);
    } catch (_) {
      if (!requestUid) {
        throw new HttpsError("unauthenticated", "Invalid auth token.");
      }
    }
  }

  if (!requestUid && !tokenUid) {
    throw new HttpsError("unauthenticated", "Recent re-authentication required.");
  }

  if (requestUid && tokenUid && requestUid !== tokenUid) {
    throw new HttpsError("permission-denied", "Re-authentication token mismatch.");
  }

  const uid = requestUid || tokenUid;
  const authTimeSec = Math.max(requestAuthTimeSec, tokenAuthTimeSec);

  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const nowSec = Math.floor(Date.now() / 1000);
  if (!authTimeSec || (nowSec - authTimeSec) > maxAgeSeconds) {
    throw new HttpsError("failed-precondition", "Please re-authenticate and try again.");
  }

  return uid;
}

async function sendNotificationToUsers(userIds, title, body, data = {}) {
  if (!userIds || userIds.length === 0) return;

  const uniqueIds = Array.from(new Set(userIds.filter(Boolean)));
  if (uniqueIds.length === 0) return;

  const tokens = [];
  const now = admin.firestore.Timestamp.now();
  for (const uid of uniqueIds) {
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) continue;
    const userData = userSnap.data() || {};
    const userTokens = Array.isArray(userData.fcmTokens) ? userData.fcmTokens : [];
    for (const t of userTokens) {
      if (typeof t === "string" && t) tokens.push(t);
    }

    await db.collection("notifications").add({
      userId: uid,
      title,
      body,
      data,
      isRead: false,
      createdAt: now,
    });
  }

  if (tokens.length === 0) return;

  const chunks = [];
  for (let i = 0; i < tokens.length; i += 500) {
    chunks.push(tokens.slice(i, i + 500));
  }

  for (const chunk of chunks) {
    await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
    });
  }
}

function toDayRange(dateValue) {
  const parsed = new Date(dateValue);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", "Invalid date value.");
  }

  const start = new Date(parsed.getFullYear(), parsed.getMonth(), parsed.getDate());
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return {
    start: admin.firestore.Timestamp.fromDate(start),
    end: admin.firestore.Timestamp.fromDate(end),
  };
}

async function pagedAttendanceQuery(baseQuery, onDocs) {
  const pageSize = 250;
  let lastDoc = null;

  while (true) {
    let query = baseQuery.limit(pageSize);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) {
      break;
    }

    await onDocs(snap.docs);

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) {
      break;
    }
  }
}

function isMissingIndexError(err) {
  const code = err && err.code ? String(err.code).toLowerCase() : "";
  const message = err && err.message
    ? String(err.message).toLowerCase()
    : String(err || "").toLowerCase();

  return code.includes("failed-precondition") ||
    message.includes("requires an index") ||
    message.includes("failed precondition");
}

function timestampToMillis(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed.getTime();
  }
  return null;
}

function normalizeDayStart(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function toDayKey(date) {
  const d = normalizeDayStart(date);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function formatDateDDMMYYYY(date) {
  const d = normalizeDayStart(date);
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}-${mm}-${yyyy}`;
}

function parseDateValue(raw) {
  if (!raw) return null;
  if (raw instanceof admin.firestore.Timestamp) {
    return raw.toDate();
  }
  if (raw instanceof Date) {
    return raw;
  }
  if (typeof raw === "string") {
    const parsed = new Date(raw);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function formatTimeHHMM(raw) {
  const date = parseDateValue(raw);
  if (!date) return "";
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

function buildDateSeries(fromDate, toDate) {
  const list = [];
  const cursor = normalizeDayStart(fromDate);
  const end = normalizeDayStart(toDate);
  while (cursor <= end) {
    list.push(new Date(cursor));
    cursor.setDate(cursor.getDate() + 1);
  }
  return list;
}

function sanitizeFilePart(value) {
  return String(value || "all")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "") || "all";
}

function roleLabel(role) {
  if (role === "site_engineer") return "site_engineer";
  if (role === "supervisor") return "supervisor";
  return String(role || "unknown");
}

function styleHeaderRow(row) {
  row.font = { bold: true, color: { argb: "FFFFFFFF" } };
  row.alignment = { vertical: "middle", horizontal: "center", wrapText: true };
  row.fill = {
    type: "pattern",
    pattern: "solid",
    fgColor: { argb: "FF1E3A5F" },
  };
  row.border = {
    top: { style: "thin", color: { argb: "FF9CA3AF" } },
    left: { style: "thin", color: { argb: "FF9CA3AF" } },
    right: { style: "thin", color: { argb: "FF9CA3AF" } },
    bottom: { style: "thin", color: { argb: "FF9CA3AF" } },
  };
}

function autoFitColumns(worksheet, min = 12, max = 44) {
  worksheet.columns.forEach((column) => {
    let width = min;
    column.eachCell({ includeEmpty: true }, (cell) => {
      const value = cell.value == null ? "" : String(cell.value);
      width = Math.max(width, Math.min(max, value.length + 2));
    });
    column.width = width;
  });
}

async function createReportDownloadUrl(fileRef, storagePath) {
  try {
    const [signedUrl] = await fileRef.getSignedUrl({
      version: "v4",
      action: "read",
      expires: Date.now() + (60 * 60 * 1000),
    });
    return signedUrl;
  } catch (err) {
    const token = crypto.randomUUID();
    await fileRef.setMetadata({
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    });
    const encodedPath = encodeURIComponent(storagePath);
    return `https://firebasestorage.googleapis.com/v0/b/${fileRef.bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
  }
}

async function loadProjectNameMap(projectIds) {
  const ids = Array.from(new Set(projectIds.filter(Boolean)));
  const nameMap = new Map();
  if (ids.length === 0) return nameMap;

  for (let i = 0; i < ids.length; i += 10) {
    const chunk = ids.slice(i, i + 10);
    const snap = await db
      .collection("projects")
      .where(admin.firestore.FieldPath.documentId(), "in", chunk)
      .get();
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      nameMap.set(doc.id, String(data.name || doc.id));
    }
  }

  return nameMap;
}

function resolveUserProjectName(user, selectedProjectId, projectNameMap) {
  if (selectedProjectId) {
    return projectNameMap.get(selectedProjectId) || selectedProjectId;
  }

  const primaryId = user.projectId || user.assignedProjects[0] || "";
  if (!primaryId) return "-";
  return projectNameMap.get(primaryId) || primaryId;
}

exports.bootstrapSuperAdmin = onCall({ region: "us-central1" }, async (request) => {
  const uid = await getAuthUid(request);

  const existing = await db
    .collection("users")
    .where("role", "==", "super_admin")
    .limit(1)
    .get();

  if (!existing.empty) {
    throw new HttpsError("failed-precondition", "Super admin already exists.");
  }

  const authUser = await admin.auth().getUser(uid);
  const now = admin.firestore.Timestamp.now();
  const name = (request.data && request.data.name) ||
    authUser.displayName ||
    "Super Admin";
  const email = authUser.email || (request.data && request.data.email) || "";
  const phone = (request.data && request.data.phone) || "";

  await db.collection("users").doc(uid).set(
    {
      uid,
      name,
      email,
      phone,
      role: "super_admin",
      assignedProjects: [],
      supervisorId: null,
      fcmTokens: [],
      isActive: true,
      isBlocked: false,
      subscriptionStatus: "active",
      faceRegistrationComplete: false,
      faceEmbeddings: {},
      faceEmbeddingVersion: "",
      faceRegisteredAt: null,
      lastFaceVerificationAt: null,
      lastFaceVerificationScore: null,
      createdAt: now,
      lastLogin: now,
    },
    { merge: true }
  );

  await db.collection("global_config").doc("app").set(
    {
      isSetupDone: true,
      setupAt: now,
      appEnabled: true,
      subscriptionStatus: "active",
      subscriptionExpiresAt: null,
      createdBy: uid,
    },
    { merge: true }
  );

  await admin.auth().setCustomUserClaims(uid, { role: "super_admin" });

  return { ok: true };
});

exports.generateAdminCode = onCall({ region: "us-central1" }, async (request) => {
  const uid = await requireSuperAdmin(request);

  const usageLimitRaw = request.data && request.data.usageLimit;
  const usageLimit = Math.max(1, parseInt(usageLimitRaw, 10) || 1);
  const expiresAtRaw = request.data && request.data.expiresAt;
  const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;

  const code = generateCode(10);
  const codeHash = hashCode(code);
  const now = admin.firestore.Timestamp.now();

  await db.collection("admin_codes").doc(codeHash).set({
    codeHash,
    codeLast4: code.slice(-4),
    createdBy: uid,
    createdAt: now,
    expiresAt: expiresAt ? admin.firestore.Timestamp.fromDate(expiresAt) : null,
    usageLimit,
    usageCount: 0,
    isUsed: false,
    isActive: true,
    lastUsedAt: null,
  });

  return {
    code,
    codeLast4: code.slice(-4),
    expiresAt: expiresAt ? expiresAt.toISOString() : null,
    usageLimit,
  };
});

exports.claimAdminCode = onCall({ region: "us-central1" }, async (request) => {
  const uid = await getAuthUid(request);
  const rawCode = (request.data && request.data.code
    ? request.data.code
    : "").toString().trim();
  const code = rawCode.toUpperCase();

  if (!code || code.length < 6) {
    throw new HttpsError("invalid-argument", "Invalid admin code.");
  }

  const codeHash = hashCode(code);
  const codeRef = db.collection("admin_codes").doc(codeHash);
  const now = admin.firestore.Timestamp.now();

  await db.runTransaction(async (tx) => {
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists) {
      throw new HttpsError("not-found", "Admin code not found.");
    }

    const codeData = codeSnap.data() || {};
    if (codeData.isActive === false) {
      throw new HttpsError("failed-precondition", "Admin code is inactive.");
    }

    if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
      throw new HttpsError("failed-precondition", "Admin code has expired.");
    }

    const usageLimit = parseInt(codeData.usageLimit || 1, 10);
    const usageCount = parseInt(codeData.usageCount || 0, 10);
    if (usageCount >= usageLimit) {
      throw new HttpsError(
        "failed-precondition",
        "Admin code usage limit reached."
      );
    }

    const authUser = await admin.auth().getUser(uid);
    const name = (request.data && request.data.name) ||
      authUser.displayName ||
      "Admin";
    const email = authUser.email || (request.data && request.data.email) || "";
    const phone = (request.data && request.data.phone) || "";

    const userRef = db.collection("users").doc(uid);
    tx.set(
      userRef,
      {
        uid,
        name,
        email,
        phone,
        role: "admin",
        assignedProjects: [],
        supervisorId: null,
        fcmTokens: [],
        isActive: true,
        isBlocked: false,
        subscriptionStatus: "active",
        faceRegistrationComplete: false,
        faceEmbeddings: {},
        faceEmbeddingVersion: "",
        faceRegisteredAt: null,
        lastFaceVerificationAt: null,
        lastFaceVerificationScore: null,
        createdAt: now,
        lastLogin: now,
      },
      { merge: true }
    );

    const nextCount = usageCount + 1;
    tx.update(codeRef, {
      usageCount: nextCount,
      lastUsedAt: now,
      isUsed: nextCount >= usageLimit,
      usedBy: admin.firestore.FieldValue.arrayUnion(uid),
    });
  });

  await admin.auth().setCustomUserClaims(uid, { role: "admin" });

  return { ok: true };
});

exports.setGlobalConfig = onCall({ region: "us-central1" }, async (request) => {
  const uid = await requireSuperAdmin(request);

  const updates = {};
  if (typeof request.data.appEnabled === "boolean") {
    updates.appEnabled = request.data.appEnabled;
  }
  if (typeof request.data.subscriptionStatus === "string") {
    const allowed = ["active", "expired", "paused"];
    if (!allowed.includes(request.data.subscriptionStatus)) {
      throw new HttpsError("invalid-argument", "Invalid subscription status.");
    }
    updates.subscriptionStatus = request.data.subscriptionStatus;
  }
  if (request.data.subscriptionExpiresAt) {
    updates.subscriptionExpiresAt = admin.firestore.Timestamp.fromDate(
      new Date(request.data.subscriptionExpiresAt)
    );
  }

  updates.updatedAt = admin.firestore.Timestamp.now();
  updates.updatedBy = uid;

  await db.collection("global_config").doc("app").set(updates, { merge: true });
  return { ok: true };
});

exports.setUserBlocked = onCall({ region: "us-central1" }, async (request) => {
  const adminUid = await requireSuperAdmin(request);

  const targetUid = request.data && request.data.uid
    ? request.data.uid.toString().trim()
    : "";
  const blocked = !!(request.data && request.data.blocked);
  const reason = (request.data && request.data.reason) || "";

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "Missing uid.");
  }

  await db.collection("users").doc(targetUid).set(
    {
      isBlocked: blocked,
      blockedAt: admin.firestore.Timestamp.now(),
      blockedBy: adminUid,
      blockedReason: reason,
    },
    { merge: true }
  );

  return { ok: true };
});

exports.assignUserProjects = onCall(
  { region: "us-central1" },
  async (request) => {
    const actor = await requireAdminOrSuper(request);
    const userId = request.data && request.data.userId
      ? request.data.userId.toString().trim()
      : "";
    const supervisorId = request.data && request.data.supervisorId
      ? request.data.supervisorId.toString().trim()
      : null;
    const projectIdsRaw = request.data && Array.isArray(request.data.projectIds)
      ? request.data.projectIds
      : [];
    const projectIds = projectIdsRaw
      .map((p) => (p || "").toString().trim())
      .filter(Boolean);

    if (!userId) {
      throw new HttpsError("invalid-argument", "Missing userId.");
    }

    const userRef = db.collection("users").doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User not found.");
    }

    const userData = userSnap.data() || {};
    const targetRole = userData.role || "";
    if (targetRole === "super_admin") {
      throw new HttpsError("permission-denied", "Cannot edit super admin.");
    }

    const prevProjects = Array.isArray(userData.assignedProjects)
      ? userData.assignedProjects
      : [];
    const toRemove = prevProjects.filter((p) => !projectIds.includes(p));

    await userRef.set(
      {
        assignedProjects: projectIds,
        projectId: projectIds[0] || null,
        supervisorId: targetRole === "site_engineer" ? supervisorId : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: actor.uid,
      },
      { merge: true }
    );

    for (const pid of projectIds) {
      await db.collection("projects").doc(pid).set(
        {
          assignedUsers: admin.firestore.FieldValue.arrayUnion(userId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    for (const pid of toRemove) {
      await db.collection("projects").doc(pid).set(
        {
          assignedUsers: admin.firestore.FieldValue.arrayRemove(userId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    return { ok: true };
  }
);

exports.resetAttendance = onCall(
  { region: "us-central1", invoker: "public" },
  async (request) => {
    const actor = await requireAdminOrSuper(request);

    const userId = request.data && request.data.userId
      ? request.data.userId.toString().trim()
      : "";
    const projectId = request.data && request.data.projectId
      ? request.data.projectId.toString().trim()
      : "";
    const allDates = !!(request.data && request.data.allDates);
    const hardDelete = !!(request.data && request.data.hardDelete);
    const reason = request.data && request.data.reason
      ? request.data.reason.toString().trim()
      : "";

    let dayRange = null;
    if (!allDates) {
      const dateRaw = request.data && request.data.date
        ? request.data.date.toString().trim()
        : "";
      if (!dateRaw) {
        throw new HttpsError("invalid-argument", "Date is required unless allDates is true.");
      }
      dayRange = toDayRange(dateRaw);
    }

    const now = admin.firestore.Timestamp.now();
    const resetLogRef = db.collection("attendance_resets").doc();
    const resetBatchId = resetLogRef.id;

    let query = db.collection("attendance");
    if (userId) {
      query = query.where("userId", "==", userId);
    }
    if (projectId) {
      query = query.where("projectId", "==", projectId);
    }
    if (dayRange) {
      query = query
        .where("date", ">=", dayRange.start)
        .where("date", "<", dayRange.end);
    }
    query = query.orderBy("date", "desc");

    let affectedCount = 0;
    const affectedUsers = new Set();

    const docMatchesScope = (data) => {
      const uid = typeof data.userId === "string" ? data.userId : "";
      const pid = typeof data.projectId === "string" ? data.projectId : "";
      if (userId && uid !== userId) return false;
      if (projectId && pid !== projectId) return false;

      if (dayRange) {
        const dateMs = timestampToMillis(data.date);
        if (dateMs == null) return false;
        if (dateMs < dayRange.start.toMillis() || dateMs >= dayRange.end.toMillis()) {
          return false;
        }
      }

      return true;
    };

    const processDocs = async (docs) => {
      const activeDocs = docs.filter((doc) => {
        const data = doc.data() || {};
        const recordStatus = data.recordStatus || "active";
        return recordStatus !== "reset";
      });

      for (let i = 0; i < activeDocs.length; i += 400) {
        const chunk = activeDocs.slice(i, i + 400);
        if (chunk.length === 0) {
          continue;
        }

        const batch = db.batch();
        for (const doc of chunk) {
          const data = doc.data() || {};
          if (hardDelete) {
            batch.delete(doc.ref);
          } else {
            batch.set(doc.ref, {
              recordStatus: "reset",
              status: "reset",
              resetBy: actor.uid,
              resetAt: now,
              resetBatchId,
              previousStatus: typeof data.status === "string" && data.status
                ? data.status
                : "present",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }

          const uid = typeof data.userId === "string" ? data.userId : "";
          if (uid) {
            affectedUsers.add(uid);
          }
        }

        await batch.commit();
        affectedCount += chunk.length;
      }
    };

    let usedScanFallback = false;
    try {
      await pagedAttendanceQuery(query, async (docs) => {
        await processDocs(docs);
      });
    } catch (err) {
      if (!isMissingIndexError(err)) {
        throw err;
      }

      usedScanFallback = true;
      const fallbackQuery = db.collection("attendance").orderBy("date", "desc");
      await pagedAttendanceQuery(fallbackQuery, async (docs) => {
        const filtered = docs.filter((doc) => docMatchesScope(doc.data() || {}));
        await processDocs(filtered);
      });
    }

    const scope = userId
      ? "single_user"
      : (projectId ? "project_bulk" : (allDates ? "global_bulk" : "date_bulk"));

    await resetLogRef.set({
      resetBatchId,
      resetBy: actor.uid,
      resetByRole: actor.role,
      scope,
      userId: userId || null,
      projectId: projectId || null,
      allDates,
      date: dayRange ? dayRange.start : null,
      hardDelete,
      reason,
      affectedCount,
      affectedUserIds: Array.from(affectedUsers),
      undone: false,
      createdAt: now,
      updatedAt: now,
    });

    if (affectedCount > 0 && affectedUsers.size > 0) {
      await sendNotificationToUsers(
        Array.from(affectedUsers),
        hardDelete ? "Attendance Removed" : "Attendance Reset",
        hardDelete
          ? "An admin permanently removed one or more attendance records."
          : "An admin reset one or more attendance records. You can mark attendance again.",
        {
          type: hardDelete ? "attendance_hard_reset" : "attendance_reset",
          resetLogId: resetLogRef.id,
          resetBatchId,
          scope,
        }
      );
    }

    return {
      ok: true,
      affectedCount,
      hardDelete,
      resetLogId: resetLogRef.id,
      undoAvailable: !hardDelete,
      undoWindowMinutes: 5,
      usedScanFallback,
    };
  }
);

exports.undoAttendanceReset = onCall(
  { region: "us-central1", invoker: "public" },
  async (request) => {
    const actor = await requireAdminOrSuper(request);
    const resetLogId = request.data && request.data.resetLogId
      ? request.data.resetLogId.toString().trim()
      : "";

    if (!resetLogId) {
      throw new HttpsError("invalid-argument", "Missing resetLogId.");
    }

    const resetLogRef = db.collection("attendance_resets").doc(resetLogId);
    const resetLogSnap = await resetLogRef.get();
    if (!resetLogSnap.exists) {
      throw new HttpsError("not-found", "Reset log not found.");
    }

    const resetLog = resetLogSnap.data() || {};
    if (resetLog.hardDelete === true) {
      throw new HttpsError("failed-precondition", "Hard delete resets cannot be undone.");
    }
    if (resetLog.undone === true) {
      throw new HttpsError("failed-precondition", "This reset has already been undone.");
    }

    const createdAt = resetLog.createdAt;
    if (!(createdAt instanceof admin.firestore.Timestamp)) {
      throw new HttpsError("failed-precondition", "Reset log is missing createdAt.");
    }

    const elapsedMs = Date.now() - createdAt.toMillis();
    const undoWindowMs = 5 * 60 * 1000;
    if (elapsedMs > undoWindowMs) {
      throw new HttpsError(
        "failed-precondition",
        "Undo window expired. Reset can only be undone within 5 minutes."
      );
    }

    const resetBatchId = (resetLog.resetBatchId || "").toString();
    if (!resetBatchId) {
      throw new HttpsError("failed-precondition", "Reset log is missing resetBatchId.");
    }

    let restoredCount = 0;
    const restoreDocs = async (docs) => {
      for (let i = 0; i < docs.length; i += 400) {
        const chunk = docs.slice(i, i + 400);
        if (chunk.length === 0) {
          continue;
        }

        const batch = db.batch();
        for (const doc of chunk) {
          const data = doc.data() || {};
          const previousStatus = typeof data.previousStatus === "string" && data.previousStatus
            ? data.previousStatus
            : "present";

          batch.set(doc.ref, {
            recordStatus: "active",
            status: previousStatus,
            resetBy: null,
            resetAt: null,
            resetBatchId: null,
            previousStatus: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }

        await batch.commit();
        restoredCount += chunk.length;
      }
    };

    let query = db
      .collection("attendance")
      .where("resetBatchId", "==", resetBatchId)
      .where("recordStatus", "==", "reset")
      .orderBy("date", "desc");

    let usedScanFallback = false;
    try {
      await pagedAttendanceQuery(query, async (docs) => {
        await restoreDocs(docs);
      });
    } catch (err) {
      if (!isMissingIndexError(err)) {
        throw err;
      }

      usedScanFallback = true;
      const fallbackQuery = db.collection("attendance").orderBy("date", "desc");
      await pagedAttendanceQuery(fallbackQuery, async (docs) => {
        const filtered = docs.filter((doc) => {
          const data = doc.data() || {};
          return data.resetBatchId === resetBatchId &&
            (data.recordStatus || "") === "reset";
        });
        await restoreDocs(filtered);
      });
    }

    await resetLogRef.set({
      undone: true,
      undoneBy: actor.uid,
      undoneAt: admin.firestore.Timestamp.now(),
      restoredCount,
      updatedAt: admin.firestore.Timestamp.now(),
    }, { merge: true });

    const affectedUserIds = Array.isArray(resetLog.affectedUserIds)
      ? resetLog.affectedUserIds.filter((u) => typeof u === "string" && u)
      : [];

    if (restoredCount > 0 && affectedUserIds.length > 0) {
      await sendNotificationToUsers(
        affectedUserIds,
        "Attendance Reset Undone",
        "An admin restored attendance records that were recently reset.",
        {
          type: "attendance_reset_undone",
          resetLogId,
          resetBatchId,
        }
      );
    }

    return {
      ok: true,
      restoredCount,
      resetLogId,
      usedScanFallback,
    };
  }
);

exports.generateAttendanceExcelReport = onCall(
  { region: "us-central1", invoker: "public", timeoutSeconds: 540, memory: "1GiB" },
  async (request) => {
    try {
      const actor = await requireAdminOrSuper(request);

    const fromRaw = request.data && request.data.fromDate
      ? request.data.fromDate.toString().trim()
      : "";
    const toRaw = request.data && request.data.toDate
      ? request.data.toDate.toString().trim()
      : "";
    const selectedProjectId = request.data && request.data.projectId
      ? request.data.projectId.toString().trim()
      : "";
    const selectedRole = request.data && request.data.role
      ? request.data.role.toString().trim()
      : "";
    const companyName = request.data && request.data.companyName
      ? request.data.companyName.toString().trim()
      : "Civil DPR";

    if (!fromRaw || !toRaw) {
      throw new HttpsError("invalid-argument", "fromDate and toDate are required.");
    }

    const fromDateParsed = new Date(fromRaw);
    const toDateParsed = new Date(toRaw);
    if (Number.isNaN(fromDateParsed.getTime()) || Number.isNaN(toDateParsed.getTime())) {
      throw new HttpsError("invalid-argument", "Invalid date range.");
    }

    const fromDate = normalizeDayStart(fromDateParsed);
    const toDate = normalizeDayStart(toDateParsed);
    if (toDate < fromDate) {
      throw new HttpsError("invalid-argument", "toDate cannot be earlier than fromDate.");
    }

    const daySeries = buildDateSeries(fromDate, toDate);
    if (daySeries.length > 366) {
      throw new HttpsError(
        "invalid-argument",
        "Date range too large. Please select up to 366 days."
      );
    }

    const allowedRoles = ["site_engineer", "supervisor"];
    if (selectedRole && !allowedRoles.includes(selectedRole)) {
      throw new HttpsError("invalid-argument", "Invalid role filter.");
    }

    const roleFilters = selectedRole ? [selectedRole] : allowedRoles;

    const users = [];
    const usersQuery = db
      .collection("users")
      .where("role", selectedRole ? "==" : "in", selectedRole || roleFilters);
    const usersSnap = await usersQuery.get();
    for (const doc of usersSnap.docs) {
      const data = doc.data() || {};
      if (data.isBlocked === true) {
        continue;
      }

      const assignedProjects = Array.isArray(data.assignedProjects)
        ? data.assignedProjects.filter((p) => typeof p === "string" && p)
        : [];
      const projectId = typeof data.projectId === "string" ? data.projectId : "";
      const inProject = !selectedProjectId ||
        projectId === selectedProjectId ||
        assignedProjects.includes(selectedProjectId);
      if (!inProject) continue;

      users.push({
        uid: doc.id,
        name: String(data.name || data.userName || "Unknown"),
        role: String(data.role || ""),
        projectId,
        assignedProjects,
      });
    }

    const usersSorted = users.sort((a, b) => a.name.localeCompare(b.name));
    const userMap = new Map(usersSorted.map((u) => [u.uid, u]));

    const toDateExclusive = new Date(toDate);
    toDateExclusive.setDate(toDateExclusive.getDate() + 1);

    let attendanceQuery = db
      .collection("attendance")
      .where("date", ">=", admin.firestore.Timestamp.fromDate(fromDate))
      .where("date", "<", admin.firestore.Timestamp.fromDate(toDateExclusive))
      .orderBy("date", "desc");

    if (selectedProjectId) {
      attendanceQuery = attendanceQuery.where("projectId", "==", selectedProjectId);
    }
    if (selectedRole) {
      attendanceQuery = attendanceQuery.where("role", "==", selectedRole);
    }

    attendanceQuery = attendanceQuery.select(
      "userId",
      "name",
      "userName",
      "role",
      "projectId",
      "projectName",
      "date",
      "status",
      "recordStatus",
      "checkIn",
      "checkOut",
      "location",
      "latitude",
      "longitude",
      "address",
      "faceVerified"
    );

    const userDayMap = new Map();
    const projectIdSet = new Set();

    for (const u of usersSorted) {
      if (u.projectId) projectIdSet.add(u.projectId);
      for (const pid of u.assignedProjects) {
        if (pid) projectIdSet.add(pid);
      }
    }
    if (selectedProjectId) {
      projectIdSet.add(selectedProjectId);
    }

    await pagedAttendanceQuery(attendanceQuery, async (docs) => {
      for (const doc of docs) {
        const data = doc.data() || {};
        if ((data.recordStatus || "active") === "reset") {
          continue;
        }

        const uid = typeof data.userId === "string" ? data.userId : "";
        if (!uid || !userMap.has(uid)) {
          continue;
        }

        const dateValue = parseDateValue(data.date);
        if (!dateValue) {
          continue;
        }

        const dayKey = toDayKey(dateValue);
        const mapKey = `${uid}|${dayKey}`;

        const checkInTime = formatTimeHHMM(data.checkIn && data.checkIn.time);
        const checkOutTime = formatTimeHHMM(data.checkOut && data.checkOut.time);
        const statusRaw = String(data.status || "").toLowerCase();
        const isPresent = statusRaw
          ? statusRaw !== "absent"
          : (checkInTime !== "" || checkOutTime !== "");

        const latitude = data.location && typeof data.location.latitude === "number"
          ? data.location.latitude
          : (typeof data.latitude === "number" ? data.latitude : null);
        const longitude = data.location && typeof data.location.longitude === "number"
          ? data.location.longitude
          : (typeof data.longitude === "number" ? data.longitude : null);

        const locationText = latitude != null && longitude != null
          ? `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`
          : "";

        const projectId = typeof data.projectId === "string" ? data.projectId : "";
        const projectName = typeof data.projectName === "string" ? data.projectName : "";
        if (projectId) {
          projectIdSet.add(projectId);
        }

        const incoming = {
          uid,
          dayKey,
          dateObj: normalizeDayStart(dateValue),
          name: String(data.name || data.userName || userMap.get(uid).name || "Unknown"),
          role: roleLabel(data.role || userMap.get(uid).role),
          projectId,
          projectName,
          status: isPresent ? "Present" : "Absent",
          checkInTime,
          checkOutTime,
          locationText,
          address: typeof data.address === "string" ? data.address : "",
          faceVerified: data.faceVerified === true,
        };

        const prev = userDayMap.get(mapKey);
        if (!prev) {
          userDayMap.set(mapKey, incoming);
          continue;
        }

        const preferIncoming = (
          (prev.status !== "Present" && incoming.status === "Present") ||
          (prev.checkOutTime === "" && incoming.checkOutTime !== "")
        );
        if (preferIncoming) {
          userDayMap.set(mapKey, incoming);
        }
      }
    });

    const projectNameMap = await loadProjectNameMap(Array.from(projectIdSet));

    const workbook = new ExcelJS.Workbook();
    workbook.creator = "Civil DPR";
    workbook.created = new Date();

    const projectLabel = selectedProjectId
      ? (projectNameMap.get(selectedProjectId) || selectedProjectId)
      : "All Projects";
    const roleLabelText = selectedRole || "All Roles";
    const rangeLabel = `${formatDateDDMMYYYY(fromDate)} to ${formatDateDDMMYYYY(toDate)}`;

    const summarySheet = workbook.addWorksheet("Summary");
    summarySheet.mergeCells("A1:G1");
    summarySheet.getCell("A1").value = companyName;
    summarySheet.getCell("A1").font = { bold: true, size: 16, color: { argb: "FF1E3A5F" } };
    summarySheet.getCell("A1").alignment = { horizontal: "center" };

    summarySheet.mergeCells("A2:G2");
    summarySheet.getCell("A2").value = `Attendance Summary Report | ${rangeLabel} | ${projectLabel} | ${roleLabelText}`;
    summarySheet.getCell("A2").alignment = { horizontal: "center" };
    summarySheet.getCell("A2").font = { bold: true, color: { argb: "FF374151" } };

    summarySheet.addRow([]);
    const summaryHeader = summarySheet.addRow([
      "Name",
      "Role",
      "Project",
      "Total Days",
      "Present Days",
      "Absent Days",
      "Attendance %",
    ]);
    styleHeaderRow(summaryHeader);

    let totalPresent = 0;
    let totalAbsent = 0;

    for (const user of usersSorted) {
      let presentDays = 0;
      for (const day of daySeries) {
        const key = `${user.uid}|${toDayKey(day)}`;
        const row = userDayMap.get(key);
        if (row && row.status === "Present") {
          presentDays += 1;
        }
      }

      const totalDays = daySeries.length;
      const absentDays = totalDays - presentDays;
      totalPresent += presentDays;
      totalAbsent += absentDays;

      const attendancePct = totalDays === 0 ? 0 : (presentDays / totalDays);
      const summaryRow = summarySheet.addRow([
        user.name,
        roleLabel(user.role),
        resolveUserProjectName(user, selectedProjectId, projectNameMap),
        totalDays,
        presentDays,
        absentDays,
        attendancePct,
      ]);
      summaryRow.getCell(7).numFmt = "0.00%";
    }

    summarySheet.addRow([]);
    const totalsRow = summarySheet.addRow([
      "TOTAL",
      "-",
      "-",
      daySeries.length * usersSorted.length,
      totalPresent,
      totalAbsent,
      daySeries.length > 0 && usersSorted.length > 0
        ? totalPresent / (daySeries.length * usersSorted.length)
        : 0,
    ]);
    totalsRow.font = { bold: true, color: { argb: "FF111827" } };
    totalsRow.getCell(7).numFmt = "0.00%";

    const dailySheet = workbook.addWorksheet("Daily Attendance");
    dailySheet.mergeCells("A1:J1");
    dailySheet.getCell("A1").value = companyName;
    dailySheet.getCell("A1").font = { bold: true, size: 15, color: { argb: "FF1E3A5F" } };
    dailySheet.getCell("A1").alignment = { horizontal: "center" };

    dailySheet.mergeCells("A2:J2");
    dailySheet.getCell("A2").value = `Daily Attendance | ${rangeLabel} | ${projectLabel} | ${roleLabelText}`;
    dailySheet.getCell("A2").alignment = { horizontal: "center" };
    dailySheet.getCell("A2").font = { bold: true, color: { argb: "FF374151" } };

    dailySheet.addRow([]);
    const dailyHeader = dailySheet.addRow([
      "Date",
      "Name",
      "Role",
      "Project",
      "Status",
      "Check-in Time",
      "Check-out Time",
      "Location (lat, long)",
      "Address",
      "Face Verified",
    ]);
    styleHeaderRow(dailyHeader);

    const detailSheet = workbook.addWorksheet("User-wise Detail");
    detailSheet.mergeCells("A1:F1");
    detailSheet.getCell("A1").value = `${companyName} | User-wise Attendance Detail`;
    detailSheet.getCell("A1").font = { bold: true, size: 14, color: { argb: "FF1E3A5F" } };
    detailSheet.getCell("A1").alignment = { horizontal: "center" };

    detailSheet.addRow([]);
    const detailHeader = detailSheet.addRow([
      "Name",
      "Date",
      "Status",
      "Check-in Time",
      "Check-out Time",
      "Project",
    ]);
    styleHeaderRow(detailHeader);

    let presentRows = 0;
    let absentRows = 0;

    for (const day of daySeries) {
      const dayKey = toDayKey(day);
      const dateLabel = formatDateDDMMYYYY(day);

      for (const user of usersSorted) {
        const mapKey = `${user.uid}|${dayKey}`;
        const row = userDayMap.get(mapKey);
        const status = row ? row.status : "Absent";
        const checkInTime = row ? row.checkInTime : "";
        const checkOutTime = row ? row.checkOutTime : "";
        const locationText = row ? row.locationText : "";
        const address = row ? row.address : "";
        const faceVerifiedText = row ? (row.faceVerified ? "Yes" : "No") : "No";
        const role = row ? row.role : roleLabel(user.role);
        const projectName = row && row.projectName
          ? row.projectName
          : resolveUserProjectName(user, selectedProjectId, projectNameMap);

        const dailyRow = dailySheet.addRow([
          dateLabel,
          user.name,
          role,
          projectName,
          status,
          checkInTime,
          checkOutTime,
          locationText,
          address,
          faceVerifiedText,
        ]);

        const detailRow = detailSheet.addRow([
          user.name,
          dateLabel,
          status,
          checkInTime,
          checkOutTime,
          projectName,
        ]);

        const statusColor = status === "Present" ? "FFE8F5E9" : "FFFFEBEE";
        const statusFontColor = status === "Present" ? "FF2E7D32" : "FFC62828";

        dailyRow.getCell(5).fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: statusColor },
        };
        dailyRow.getCell(5).font = { bold: true, color: { argb: statusFontColor } };

        detailRow.getCell(3).fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: statusColor },
        };
        detailRow.getCell(3).font = { bold: true, color: { argb: statusFontColor } };

        if (status === "Present") {
          presentRows += 1;
        } else {
          absentRows += 1;
        }
      }
    }

    [summarySheet, dailySheet, detailSheet].forEach((sheet) => {
      sheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
        if (rowNumber <= 4) return;
        row.alignment = { vertical: "middle", horizontal: "left", wrapText: true };
      });
    });

    autoFitColumns(summarySheet, 12, 34);
    autoFitColumns(dailySheet, 12, 48);
    autoFitColumns(detailSheet, 12, 32);

    const projectFilePart = selectedProjectId
      ? sanitizeFilePart(projectNameMap.get(selectedProjectId) || selectedProjectId)
      : "all_projects";
    const dateFilePart = fromDate.getTime() === toDate.getTime()
      ? formatDateDDMMYYYY(fromDate)
      : `${formatDateDDMMYYYY(fromDate)}_to_${formatDateDDMMYYYY(toDate)}`;
    const fileName = `attendance_report_${projectFilePart}_${dateFilePart}.xlsx`;

    const buffer = await workbook.xlsx.writeBuffer();
    const storagePath = `attendance_reports/${actor.uid}/${Date.now()}_${fileName}`;
    const bucket = admin.storage().bucket();
    const fileRef = bucket.file(storagePath);

    await fileRef.save(Buffer.from(buffer), {
      resumable: false,
      contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      metadata: {
        cacheControl: "private, max-age=3600",
      },
    });

    const downloadUrl = await createReportDownloadUrl(fileRef, storagePath);

    await db.collection("attendance_report_exports").add({
      generatedBy: actor.uid,
      generatedByRole: actor.role,
      fromDate: admin.firestore.Timestamp.fromDate(fromDate),
      toDate: admin.firestore.Timestamp.fromDate(toDate),
      projectId: selectedProjectId || null,
      role: selectedRole || null,
      usersCount: usersSorted.length,
      presentRows,
      absentRows,
      fileName,
      storagePath,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      fileName,
      downloadUrl,
      usersCount: usersSorted.length,
      totalDays: daySeries.length,
      presentRows,
      absentRows,
      generatedAt: new Date().toISOString(),
    };
    } catch (err) {
      if (err instanceof HttpsError) {
        throw err;
      }

      const message = err && err.message ? err.message : "unknown error";
      console.error("generateAttendanceExcelReport failed", {
        message,
        stack: err && err.stack ? err.stack : "",
      });
      throw new HttpsError("internal", `Excel generation failed: ${message}`);
    }
  }
);

async function deleteDocsByQuery(baseQuery, pageSize = 200, onDocs = null) {
  while (true) {
    const snap = await baseQuery.limit(pageSize).get();
    if (snap.empty) break;

    if (onDocs) {
      await onDocs(snap.docs);
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    if (snap.size < pageSize) break;
  }
}

async function safeDeleteStoragePrefix(prefix) {
  try {
    await admin.storage().bucket().deleteFiles({ prefix, force: true });
  } catch (err) {
    console.warn("Storage prefix delete skipped", { prefix, message: err && err.message ? err.message : String(err) });
  }
}

async function deleteCollectionInBatches(collectionName, batchSize = 500) {
  let deleted = 0;
  while (true) {
    const snap = await db.collection(collectionName).limit(batchSize).get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snap.size;

    if (snap.size < batchSize) break;
  }
  return deleted;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function purgeUserData(uid) {
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();

  // Remove user from any assignedUsers arrays (source of truth is project docs).
  await deleteDocsByQuery(
    db.collection("projects").where("assignedUsers", "array-contains", uid),
    120,
    async (docs) => {
      const batch = db.batch();
      for (const doc of docs) {
        batch.set(
          doc.ref,
          {
            assignedUsers: admin.firestore.FieldValue.arrayRemove(uid),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      await batch.commit();
    }
  );

  // If a supervisor deletes account, detach engineers from missing supervisor.
  await deleteDocsByQuery(
    db.collection("users").where("supervisorId", "==", uid),
    150,
    async (docs) => {
      const batch = db.batch();
      for (const doc of docs) {
        batch.set(
          doc.ref,
          {
            supervisorId: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      await batch.commit();
    }
  );

  // Delete user-owned operational docs.
  const dprDocIds = [];
  await deleteDocsByQuery(
    db.collection("dprs").where("uploadedById", "==", uid),
    120,
    async (docs) => {
      for (const doc of docs) {
        dprDocIds.push(doc.id);
      }
    }
  );

  await deleteDocsByQuery(
    db.collection("attendance").where("userId", "==", uid),
    220
  );

  await deleteDocsByQuery(
    db.collection("leave_requests").where("userId", "==", uid),
    220
  );

  await deleteDocsByQuery(
    db.collection("notifications").where("userId", "==", uid),
    220
  );

  // Delete user-owned files from Cloud Storage.
  await safeDeleteStoragePrefix(`attendance_photos/${uid}/`);
  await safeDeleteStoragePrefix(`profile_photos/${uid}.`);
  for (const dprId of dprDocIds) {
    await safeDeleteStoragePrefix(`dpr_photos/${dprId}_`);
  }

  if (userSnap.exists) {
    await userRef.delete();
  }
}

exports.deleteUser = onCall({ region: "us-central1" }, async (request) => {
  const actor = await requireAdminOrSuper(request);
  const uid = request.data && request.data.uid
    ? request.data.uid.toString().trim()
    : "";

  if (!uid) {
    throw new HttpsError("invalid-argument", "Missing uid.");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "User not found.");
  }

  const userData = userSnap.data() || {};
  if (userData.role === "super_admin") {
    throw new HttpsError("permission-denied", "Cannot delete super admin.");
  }

  await purgeUserData(uid);
  await admin.auth().deleteUser(uid);

  return { ok: true, deletedBy: actor.uid };
});

exports.deleteMyAccount = onCall({ region: "us-central1" }, async (request) => {
  const uid = await getAuthUid(request);

  await purgeUserData(uid);
  await admin.auth().deleteUser(uid);
  return { ok: true };
});

exports.resetApp = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "1GiB",
    invoker: ["public"],
  },
  async (request) => {
    const uid = await requireSuperAdmin(request);
    const reauthUid = await requireRecentReauth(request, 300);
    if (uid !== reauthUid) {
      throw new HttpsError("permission-denied", "Re-authentication mismatch.");
    }

    const confirmationText = (request.data && request.data.confirmationText
      ? request.data.confirmationText.toString().trim()
      : "");
    const doubleConfirm = request.data && request.data.doubleConfirm === true;

    if (confirmationText !== "RESET APP") {
      throw new HttpsError("invalid-argument", "Invalid reset confirmation text.");
    }
    if (!doubleConfirm) {
      throw new HttpsError("failed-precondition", "Double confirmation required.");
    }

    const runId = `reset_${Date.now()}_${uid.slice(0, 6)}`;
    const lockRef = db.collection("system_state").doc("reset_lock");
    const nowTs = admin.firestore.Timestamp.now();

    await db.runTransaction(async (tx) => {
      const lockSnap = await tx.get(lockRef);
      const data = lockSnap.data() || {};
      if (data.isRunning === true) {
        throw new HttpsError("failed-precondition", "Another reset operation is already running.");
      }
      tx.set(lockRef, {
        isRunning: true,
        runId,
        startedAt: nowTs,
        startedBy: uid,
      }, { merge: true });
    });

    let deletedAuthUsers = 0;
    const deletedCollections = {};

    try {
      await db.collection("system_logs").add({
        action: "FULL_RESET",
        performedBy: uid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "started",
        runId,
      });

      // Bonus safety: delay execution for 10 seconds after confirmation.
      await sleep(10000);

      const authUser = await admin.auth().getUser(uid);
      const now = admin.firestore.Timestamp.now();
      const superAdminName = authUser.displayName || "Super Admin";
      const superAdminEmail = authUser.email || "";
      const superAdminPhone = authUser.phoneNumber || "";

      // Storage cleanup.
      const storagePrefixes = [
        "attendance_photos/",
        "profile_photos/",
        "dpr_photos/",
        "attendance_images/",
        "profile_images/",
        "attendance_reports/",
      ];
      for (const prefix of storagePrefixes) {
        await safeDeleteStoragePrefix(prefix);
      }

      // Firestore cleanup in chunks.
      const collectionsToDelete = [
        "attendance",
        "projects",
        "dprs",
        "leave_requests",
        "notifications",
        "attendance_resets",
        "attendance_report_exports",
        "admin_codes",
        "analytics",
        "users",
      ];

      for (const collectionName of collectionsToDelete) {
        deletedCollections[collectionName] = await deleteCollectionInBatches(collectionName, 500);
      }

      // Auth cleanup: remove everyone except current super admin.
      let pageToken;
      do {
        const page = await admin.auth().listUsers(1000, pageToken);
        pageToken = page.pageToken;
        const deleteUids = page.users
          .map((u) => u.uid)
          .filter((id) => id !== uid);
        if (deleteUids.length > 0) {
          const result = await admin.auth().deleteUsers(deleteUids);
          deletedAuthUsers += result.successCount;
        }
      } while (pageToken);

      // Reinitialize base app state with default super admin profile.
      await db.collection("users").doc(uid).set({
        uid,
        name: superAdminName,
        email: superAdminEmail,
        phone: superAdminPhone,
        role: "super_admin",
        assignedProjects: [],
        supervisorId: null,
        fcmTokens: [],
        isActive: true,
        isBlocked: false,
        subscriptionStatus: "active",
        faceRegistrationComplete: false,
        faceEmbeddings: {},
        faceEmbeddingVersion: "",
        faceRegisteredAt: null,
        lastFaceVerificationAt: null,
        lastFaceVerificationScore: null,
        createdAt: now,
        lastLogin: now,
      }, { merge: true });

      await db.collection("global_config").doc("app").set({
        isSetupDone: true,
        setupAt: now,
        appEnabled: true,
        subscriptionStatus: "active",
        subscriptionExpiresAt: null,
        createdBy: uid,
        updatedAt: now,
        updatedBy: uid,
      }, { merge: true });

      await admin.auth().setCustomUserClaims(uid, { role: "super_admin" });

      await db.collection("system_logs").add({
        action: "FULL_RESET",
        performedBy: uid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "completed",
        runId,
        deletedAuthUsers,
        deletedCollections,
      });

      return {
        ok: true,
        runId,
        deletedAuthUsers,
        deletedCollections,
      };
    } catch (err) {
      await db.collection("system_logs").add({
        action: "FULL_RESET",
        performedBy: uid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "failed",
        runId,
        error: err && err.message ? err.message : String(err),
      });

      if (err instanceof HttpsError) {
        throw err;
      }
      throw new HttpsError("internal", "Reset failed. Please try again.");
    } finally {
      await lockRef.set({
        isRunning: false,
        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastRunId: runId,
      }, { merge: true });
    }
  }
);

exports.reviewLeave = onCall(
  { region: "us-central1", invoker: "public" },
  async (request) => {
    const actor = await requireAdminOrSuper(request);
    const leaveId = request.data && request.data.leaveId
      ? request.data.leaveId.toString().trim()
      : "";
    const status = request.data && request.data.status
      ? request.data.status.toString().trim()
      : "";
    const adminResponse = request.data && request.data.adminResponse
      ? request.data.adminResponse.toString().trim()
      : "";

    if (!leaveId) {
      throw new HttpsError("invalid-argument", "Missing leaveId.");
    }
    if (status !== "approved" && status !== "rejected") {
      throw new HttpsError("invalid-argument", "Invalid leave status.");
    }

    const leaveRef = db.collection("leave_requests").doc(leaveId);
    const leaveSnap = await leaveRef.get();
    if (!leaveSnap.exists) {
      throw new HttpsError("not-found", "Leave request not found.");
    }

    const leave = leaveSnap.data() || {};
    await leaveRef.set(
      {
        status,
        adminResponse,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewedBy: actor.uid,
      },
      { merge: true }
    );

    const userId = leave.userId || "";
    if (userId) {
      await sendNotificationToUsers(
        [userId],
        `Leave ${status}`,
        status === "approved"
          ? "Your leave request has been approved."
          : "Your leave request has been rejected.",
        {
          type: "leave_reviewed",
          leaveId,
          status,
        }
      );
    }

    return { ok: true };
  }
);

exports.onLeaveRequestCreated = onDocumentCreated(
  {
    document: "leave_requests/{leaveId}",
    region: "us-central1",
  },
  async (event) => {
    const leave = event.data && event.data.data ? event.data.data() : null;
    if (!leave) return;

    const requesterName = leave.userName || "A user";
    const projectId = leave.projectId || "";

    const adminsSnap = await db
      .collection("users")
      .where("role", "in", ["admin", "super_admin"])
      .where("isBlocked", "==", false)
      .get();

    const adminIds = adminsSnap.docs.map((d) => d.id);

    await sendNotificationToUsers(
      adminIds,
      "New Leave Request",
      `${requesterName} requested leave for project ${projectId}.`,
      {
        type: "leave_requested",
        leaveId: event.params.leaveId,
        userId: leave.userId || "",
      }
    );
  }
);
