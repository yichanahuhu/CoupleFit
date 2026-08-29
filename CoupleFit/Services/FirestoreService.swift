import FirebaseFirestore
import FirebaseFirestoreSwift
import Foundation

// MARK: - Firestore 服务

/// 所有 Firestore 读写集中在此。
/// 读取默认走 `getDocument`（source 优先服务器，离线时回退缓存），
/// 实时更新统一走 addSnapshotListener。
///
/// 单例 + 内部无可变状态，标记为 Sendable 以便从 @MainActor 的 AppState 直接调用。
final class FirestoreService: @unchecked Sendable {

    static let shared = FirestoreService()

    private let db: Firestore

    private init() {
        db = Firestore.firestore()
        // 离线持久化：断网时仍可读取缓存，写入会在恢复网络后自动提交
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024)
        db.settings = settings
    }

    // MARK: - users

    func fetchUser(_ uid: String) async throws -> UserProfile? {
        try await db.collection(Constants.colUsers).document(uid).getDocument().data(as: UserProfile.self)
    }

    func createUser(_ profile: UserProfile) async throws {
        guard let uid = profile.id else { throw AppError.notSignedIn }
        try db.collection(Constants.colUsers).document(uid).setData(from: profile)
    }

    /// 局部更新，避免覆盖 partnerId 等并发字段
    func updateUserFields(uid: String, fields: [String: Any]) async throws {
        try await db.collection(Constants.colUsers).document(uid).updateData(fields)
    }

    /// 追加快照 token。同一账号可能在多台设备登录（如 iPhone + iPad），
    /// 所以用 arrayUnion 累加而非覆盖，避免后登录的设备顶掉先登录的。
    func addFCMToken(uid: String, token: String) async throws {
        try await updateUserFields(uid: uid, fields: ["fcmTokens": FieldValue.arrayUnion([token])])
    }

    /// 只移除当前设备这一个 token，不影响同账号下的其他设备
    func removeFCMToken(uid: String, token: String) async throws {
        try await updateUserFields(uid: uid, fields: ["fcmTokens": FieldValue.arrayRemove([token])])
    }

    func listenUser(_ uid: String, onChange: @escaping (UserProfile?) -> Void) -> ListenerRegistration {
        db.collection(Constants.colUsers).document(uid)
            .addSnapshotListener { snapshot, error in
                guard error == nil else { onChange(nil); return }
                guard let snapshot, snapshot.exists else { onChange(nil); return }
                onChange(try? snapshot.data(as: UserProfile.self))
            }
    }

    // MARK: - pairCodes

    func createPairCode(_ pairCode: PairCode) async throws {
        try db.collection(Constants.colPairCodes)
            .document(pairCode.code)
            .setData(from: pairCode)
    }

    func fetchPairCode(_ code: String) async throws -> PairCode? {
        let snapshot = try await db.collection(Constants.colPairCodes).document(code).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: PairCode.self)
    }

    func deletePairCode(_ code: String) async throws {
        try await db.collection(Constants.colPairCodes).document(code).delete()
    }

    /// 清理当前用户已过期的配对码（生成新码时顺手调用）
    func deleteExpiredPairCodes(creatorUserId: String) async throws {
        let snapshot = try await db.collection(Constants.colPairCodes)
            .whereField("creatorUserId", isEqualTo: creatorUserId)
            .getDocuments()
        for document in snapshot.documents where document.documentID.count == Constants.pairCodeLength {
            let pairCode = try? document.data(as: PairCode.self)
            if pairCode?.isExpired == true {
                try? await document.reference.delete()
            }
        }
    }

    // MARK: - 情侣绑定

    /// 双向写入 partnerId，并设置双方 users 文档（若不存在则创建）
    func bindPartners(uidA: String, uidB: String) async throws {
        try await db.runTransaction { transaction, errorPointer in
            let refA = self.db.collection(Constants.colUsers).document(uidA)
            let refB = self.db.collection(Constants.colUsers).document(uidB)

            do {
                let snapA = try transaction.getDocument(refA)
                let snapB = try transaction.getDocument(refB)

                guard snapA.exists, snapB.exists else {
                    errorPointer?.pointee = NSError(
                        domain: "CoupleFit",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: AppError.userDocumentMissing.errorDescription ?? ""]
                    )
                    return nil
                }

                // 校验双方当前都未绑定（或已绑定彼此）
                let partnerA = snapA.data()?["partnerId"] as? String
                let partnerB = snapB.data()?["partnerId"] as? String

                if let partnerA, !partnerA.isEmpty, partnerA != uidB {
                    errorPointer?.pointee = NSError(
                        domain: "CoupleFit",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: AppError.alreadyPairedWithOther.errorDescription ?? ""]
                    )
                    return nil
                }
                if let partnerB, !partnerB.isEmpty, partnerB != uidA {
                    errorPointer?.pointee = NSError(
                        domain: "CoupleFit",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: AppError.alreadyPairedWithOther.errorDescription ?? ""]
                    )
                    return nil
                }

                transaction.updateData(["partnerId": uidB], forDocument: refA)
                transaction.updateData(["partnerId": uidA], forDocument: refB)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            return nil
        }
    }

    /// 解绑：清除双方的 partnerId
    func unbindPartners(myUID: String, partnerUID: String) async throws {
        try await db.runBatch { batch in
            batch.updateData(["partnerId": FieldValue.delete()],
                             forDocument: self.db.collection(Constants.colUsers).document(myUID))
            batch.updateData(["partnerId": FieldValue.delete()],
                             forDocument: self.db.collection(Constants.colUsers).document(partnerUID))
        }
    }

    // MARK: - exerciseRecords

    /// 监听某人某一天的记录（首页实时同步用）
    func listenRecords(userId: String,
                       dateString: String,
                       onChange: @escaping ([ExerciseRecord]) -> Void) -> ListenerRegistration {
        db.collection(Constants.colExerciseRecords)
            .whereField("userId", isEqualTo: userId)
            .whereField("dateString", isEqualTo: dateString)
            .addSnapshotListener { snapshot, error in
                guard error == nil else { return }
                guard let snapshot else { return }
                let records = snapshot.documents.compactMap { try? $0.data(as: ExerciseRecord.self) }
                onChange(records.sorted { $0.startTime.dateValue() < $1.startTime.dateValue() })
            }
    }

    /// 监听某人最近 N 天的记录（历史 / 统计用）
    func listenRecentRecords(userId: String,
                             sinceDateString: String,
                             onChange: @escaping ([ExerciseRecord]) -> Void) -> ListenerRegistration {
        db.collection(Constants.colExerciseRecords)
            .whereField("userId", isEqualTo: userId)
            .whereField("dateString", isGreaterThanOrEqualTo: sinceDateString)
            .addSnapshotListener { snapshot, error in
                guard error == nil else { return }
                guard let snapshot else { return }
                let records = snapshot.documents.compactMap { try? $0.data(as: ExerciseRecord.self) }
                onChange(records.sorted { $0.startTime.dateValue() > $1.startTime.dateValue() })
            }
    }

    @discardableResult
    func addRecord(_ record: ExerciseRecord) async throws -> String {
        let reference = try db.collection(Constants.colExerciseRecords).addDocument(from: record)
        return reference.documentID
    }

    func updateRecord(_ record: ExerciseRecord) async throws {
        guard let id = record.id else { return }
        try db.collection(Constants.colExerciseRecords).document(id).setData(from: record, merge: false)
    }

    func deleteRecord(_ record: ExerciseRecord) async throws {
        guard let id = record.id else { return }
        try await db.collection(Constants.colExerciseRecords).document(id).delete()
    }

    // MARK: - goals

    func listenGoal(userId: String, onChange: @escaping (Goal?) -> Void) -> ListenerRegistration {
        db.collection(Constants.colGoals).document(userId)
            .addSnapshotListener { snapshot, error in
                guard error == nil else { return }
                guard let snapshot, snapshot.exists else { onChange(nil); return }
                onChange(try? snapshot.data(as: Goal.self))
            }
    }

    func saveGoal(_ goal: Goal) async throws {
        try db.collection(Constants.colGoals).document(goal.userId).setData(from: goal)
    }

    // MARK: - likes

    /// 监听某人在某天收到的赞（首页对方卡片实时显示）
    func listenLikes(toUserId: String,
                     dateString: String,
                     onChange: @escaping ([Like]) -> Void) -> ListenerRegistration {
        db.collection(Constants.colLikes)
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("dateString", isEqualTo: dateString)
            .addSnapshotListener { snapshot, error in
                guard error == nil else { return }
                guard let snapshot else { return }
                onChange(snapshot.documents.compactMap { try? $0.data(as: Like.self) })
            }
    }

    /// 我今天是否已经给对方点过赞（幂等：同一天只记一次）
    func fetchMyLike(fromUserId: String, toUserId: String, dateString: String) async throws -> Like? {
        let snapshot = try await db.collection(Constants.colLikes)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("dateString", isEqualTo: dateString)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first?.data(as: Like.self)
    }

    @discardableResult
    func addLike(_ like: Like) async throws -> String {
        let reference = try db.collection(Constants.colLikes).addDocument(from: like)
        return reference.documentID
    }

    func removeLike(_ like: Like) async throws {
        guard let id = like.id else { return }
        try await db.collection(Constants.colLikes).document(id).delete()
    }
}
