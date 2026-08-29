import Foundation

// MARK: - 数据服务（LeanCloud REST）

/// 原 Firestore 读写统一替换为 LeanCloud REST 调用。
/// 实时更新在 AppState 中通过轮询（refreshAll）实现，这里只提供 CRUD 与查询。
///
/// 单例 + 内部无可变状态，标记为 Sendable 以便从 @MainActor 的 AppState 直接调用。
final class FirestoreService: @unchecked Sendable {

    static let shared = FirestoreService()

    private let client = LeanCloudClient.shared

    private init() {}

    // MARK: - 编码辅助

    /// 把模型编码为字典，并剔除 objectId / createdTs 等由服务端管理的字段（创建时不需要）
    private func fieldsForCreate<T: Encodable>(_ value: T) throws -> [String: Any] {
        var dict = try encodeDict(value)
        dict.removeValue(forKey: "objectId")
        dict.removeValue(forKey: "createdTs")
        return dict
    }

    /// 把模型编码为字典，剔除 objectId（更新时 objectId 在 URL 中，不在 body）
    private func fieldsForUpdate<T: Encodable>(_ value: T) throws -> [String: Any] {
        var dict = try encodeDict(value)
        dict.removeValue(forKey: "objectId")
        return dict
    }

    private func encodeDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.unknown("数据编码失败")
        }
        return dict
    }

    // MARK: - UserProfile

    /// 按 ownerId 查业务资料
    func fetchUser(ownerId: String) async throws -> UserProfile? {
        let query = [LeanCloudClient.whereItem(["ownerId": ownerId])]
        let results = try await client.getResults(className: Constants.colUsers, query: query)
        guard let first = results.first else { return nil }
        return try client.decode(first, as: UserProfile.self)
    }

    /// 创建业务资料，返回 objectId
    @discardableResult
    func createUser(_ profile: UserProfile) async throws -> String {
        let fields = try fieldsForCreate(profile)
        return try await client.createObject(className: Constants.colUsers, fields: fields)
    }

    /// 局部更新（避免覆盖 partnerId 等并发字段）
    func updateUserFields(objectId: String, fields: [String: Any]) async throws {
        try await client.updateObject(className: Constants.colUsers, objectId: objectId, fields: fields)
    }

    // MARK: - pairCodes

    func createPairCode(_ pairCode: PairCode) async throws {
        let fields = try fieldsForCreate(pairCode)
        _ = try await client.createObject(className: Constants.colPairCodes, fields: fields)
    }

    func fetchPairCode(_ code: String) async throws -> PairCode? {
        let query = [LeanCloudClient.whereItem(["code": code])]
        let results = try await client.getResults(className: Constants.colPairCodes, query: query)
        guard let first = results.first else { return nil }
        return try client.decode(first, as: PairCode.self)
    }

    func deletePairCode(_ code: String) async throws {
        let query = [LeanCloudClient.whereItem(["code": code])]
        let results = try await client.getResults(className: Constants.colPairCodes, query: query)
        if let first = results.first, let oid = first["objectId"] as? String {
            try await client.deleteObject(className: Constants.colPairCodes, objectId: oid)
        }
    }

    /// 清理当前用户已过期的配对码
    func deleteExpiredPairCodes(creatorUserId: String) async throws {
        let query = [LeanCloudClient.whereItem(["creatorUserId": creatorUserId])]
        let results = try await client.getResults(className: Constants.colPairCodes, query: query)
        for dict in results {
            guard let oid = dict["objectId"] as? String else { continue }
            if let pairCode = try? client.decode(dict, as: PairCode.self), pairCode.isExpired {
                try? await client.deleteObject(className: Constants.colPairCodes, objectId: oid)
            }
        }
    }

    // MARK: - 情侣绑定

    /// 双向写入 partnerId。LeanCloud REST 无事务，用两次 PUT 实现（本地自用，偶发并发可忽略）。
    func bindPartners(uidA: String, uidB: String) async throws {
        let profileA = try await fetchUser(ownerId: uidA)
        let profileB = try await fetchUser(ownerId: uidB)
        guard let oidA = profileA?.id, let oidB = profileB?.id else {
            throw AppError.userDocumentMissing
        }
        try await client.updateObject(className: Constants.colUsers, objectId: oidA, fields: ["partnerId": uidB])
        try await client.updateObject(className: Constants.colUsers, objectId: oidB, fields: ["partnerId": uidA])
    }

    /// 解绑：清除双方的 partnerId
    func unbindPartners(myUID: String, partnerUID: String) async throws {
        if let oid = try await fetchUser(ownerId: myUID)?.id {
            try await client.updateObject(className: Constants.colUsers, objectId: oid, fields: ["partnerId": NSNull()])
        }
        if let oid = try await fetchUser(ownerId: partnerUID)?.id {
            try await client.updateObject(className: Constants.colUsers, objectId: oid, fields: ["partnerId": NSNull()])
        }
    }

    // MARK: - exerciseRecords

    func fetchRecords(userId: String, dateString: String) async throws -> [ExerciseRecord] {
        let query = [
            LeanCloudClient.whereItem(["userId": userId, "dateString": dateString]),
            URLQueryItem(name: "order", value: "startTime")
        ]
        let results = try await client.getResults(className: Constants.colExerciseRecords, query: query)
        return results.compactMap { try? client.decode($0, as: ExerciseRecord.self) }
    }

    func fetchRecentRecords(userId: String, sinceDateString: String) async throws -> [ExerciseRecord] {
        let query = [
            LeanCloudClient.whereItem(["userId": userId, "dateString": ["$gte": sinceDateString]]),
            URLQueryItem(name: "order", value: "-startTime")
        ]
        let results = try await client.getResults(className: Constants.colExerciseRecords, query: query)
        return results.compactMap { try? client.decode($0, as: ExerciseRecord.self) }
    }

    @discardableResult
    func addRecord(_ record: ExerciseRecord) async throws -> String {
        let fields = try fieldsForCreate(record)
        return try await client.createObject(className: Constants.colExerciseRecords, fields: fields)
    }

    func updateRecord(_ record: ExerciseRecord) async throws {
        guard let id = record.id else { return }
        let fields = try fieldsForUpdate(record)
        try await client.updateObject(className: Constants.colExerciseRecords, objectId: id, fields: fields)
    }

    func deleteRecord(_ record: ExerciseRecord) async throws {
        guard let id = record.id else { return }
        try await client.deleteObject(className: Constants.colExerciseRecords, objectId: id)
    }

    // MARK: - goals

    func fetchGoal(userId: String) async throws -> Goal? {
        let query = [LeanCloudClient.whereItem(["userId": userId])]
        let results = try await client.getResults(className: Constants.colGoals, query: query)
        guard let first = results.first else { return nil }
        return try client.decode(first, as: Goal.self)
    }

    func saveGoal(_ goal: Goal) async throws {
        var fields = try fieldsForUpdate(goal)
        fields["userId"] = goal.userId
        if let id = goal.id {
            try await client.updateObject(className: Constants.colGoals, objectId: id, fields: fields)
        } else {
            let oid = try await client.createObject(className: Constants.colGoals, fields: fields)
            _ = oid
        }
    }

    // MARK: - likes

    func fetchLikes(toUserId: String, dateString: String) async throws -> [Like] {
        let query = [
            LeanCloudClient.whereItem(["toUserId": toUserId, "dateString": dateString]),
            URLQueryItem(name: "order", value: "-createdTs")
        ]
        let results = try await client.getResults(className: Constants.colLikes, query: query)
        return results.compactMap { try? client.decode($0, as: Like.self) }
    }

    func fetchMyLike(fromUserId: String, toUserId: String, dateString: String) async throws -> Like? {
        let query = [
            LeanCloudClient.whereItem([
                "fromUserId": fromUserId,
                "toUserId": toUserId,
                "dateString": dateString
            ]),
            URLQueryItem(name: "limit", value: "1")
        ]
        let results = try await client.getResults(className: Constants.colLikes, query: query)
        return results.first.flatMap { try? client.decode($0, as: Like.self) }
    }

    @discardableResult
    func addLike(_ like: Like) async throws -> String {
        let fields = try fieldsForCreate(like)
        return try await client.createObject(className: Constants.colLikes, fields: fields)
    }

    func removeLike(_ like: Like) async throws {
        guard let id = like.id else { return }
        try await client.deleteObject(className: Constants.colLikes, objectId: id)
    }
}
