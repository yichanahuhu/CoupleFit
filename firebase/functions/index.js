/**
 * CoupleFit —— Cloud Functions
 *
 * 唯一职责：代替客户端发送 FCM 推送（「提醒对方」功能）。
 *
 * 为什么需要它？
 *   客户端不持有 Firebase Server Key，无法直接调用 FCM HTTP v1 API。
 *   若把 Server Key 打包进 App，任何人都能反编译拿到并冒充你发推送。
 *   因此由这段可信后端代码代为发送。
 *
 * 部署：
 *   cd firebase/functions
 *   npm install
 *   firebase deploy --only functions
 *
 * 部署后把输出的 HTTPS URL 填到：
 *   - CoupleFit/Resources/Info.plist 的 RemindEndpoint，或
 *   - Services/MessagingService.swift 的 remindEndpoint 默认值
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/**
 * POST /remindPartner
 *
 * Body: { partnerUID: string, title: string, body: string, exerciseType?: string }
 *
 * 校验：调用者必须是已登录用户，且与 partnerUID 存在情侣关系，
 *       否则任何人都能拿到 UID 后给别人狂发推送。
 */
exports.remindPartner = functions
  .region("asia-east1")
  .https.onRequest(async (req, res) => {
    // CORS：本地调试时可放开，生产建议只允许自己的 App
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    try {
      // 1. 校验调用者身份（App 需带 Firebase ID Token）
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ")
        ? authHeader.slice(7)
        : null;

      if (!idToken) {
        res.status(401).json({ error: "Missing ID token" });
        return;
      }

      const decoded = await admin.auth().verifyIdToken(idToken);
      const callerUID = decoded.uid;

      const { partnerUID, title, body } = req.body || {};

      if (!partnerUID || !title || !body) {
        res.status(400).json({ error: "Missing partnerUID / title / body" });
        return;
      }

      // 2. 校验情侣关系：单向校验即可，因为绑定是双向写入的
      const callerSnap = await db.collection("users").doc(callerUID).get();
      if (!callerSnap.exists || callerSnap.data().partnerId !== partnerUID) {
        res.status(403).json({ error: "Not paired with this user" });
        return;
      }

      // 3. 取对方的 FCM token
      const partnerSnap = await db.collection("users").doc(partnerUID).get();
      if (!partnerSnap.exists) {
        res.status(404).json({ error: "Partner not found" });
        return;
      }

      // 3. 取对方的 FCM token。
      //    注意是数组：一个账号可能同时登录多台设备（iPhone + iPad），要全部推送。
      const tokens = partnerSnap.data().fcmTokens || [];
      if (tokens.length === 0) {
        // 对方未开启通知或还没上报 token，视为成功，不打扰调用者
        res.status(200).json({ sent: false, reason: "partner has no FCM token" });
        return;
      }

      // 4. 一次性推送给对方的所有设备
      const response = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: {
          type: "remind_partner",
          fromUserId: callerUID,
          exerciseType: String(req.body.exerciseType || ""),
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              "content-available": 1,
            },
          },
        },
      });

      // 5. 清理失效 token。用户卸载 App 或换机后旧 token 会永久失效，
      //    不清理的话 fcmTokens 会越攒越多，白白消耗推送配额。
      if (response.failureCount > 0) {
        const deadCodes = [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ];
        const deadTokens = [];
        response.responses.forEach((r, index) => {
          if (!r.success && deadCodes.includes(r.error && r.error.code)) {
            deadTokens.push(tokens[index]);
          }
        });

        if (deadTokens.length > 0) {
          await db.collection("users").doc(partnerUID).update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...deadTokens),
          });
          functions.logger.info(`Removed ${deadTokens.length} dead FCM tokens`);
        }
      }

      res.status(200).json({
        sent: true,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
    } catch (error) {
      functions.logger.error("remindPartner failed", error);
      res.status(500).json({ error: "Internal error" });
    }
  });

/**
 * 清理过期配对码。每 30 分钟跑一次，避免 pairCodes 集合无限膨胀。
 */
exports.cleanupExpiredPairCodes = functions
  .region("asia-east1")
  .pubsub.schedule("every 30 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const expired = await db
      .collection("pairCodes")
      .where("expiresAt", "<", now)
      .limit(500)
      .get();

    const batch = db.batch();
    expired.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    functions.logger.info(`Cleaned up ${expired.size} expired pair codes`);
    return null;
  });
