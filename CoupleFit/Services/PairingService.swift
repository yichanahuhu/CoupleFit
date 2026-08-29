import Foundation

// MARK: - 配对服务

/// 6 位配对码的生成、校验与绑定/解绑。
/// 配对码 10 分钟有效，绑定成功后立即删除。
struct PairingService {

    private let firestore = FirestoreService.shared

    /// 生成 6 位数字配对码，冲突时重试
    func generateCode(for creatorUserId: String) async throws -> PairCode {
        try? await firestore.deleteExpiredPairCodes(creatorUserId: creatorUserId)

        for _ in 0..<10 {
            let code = Self.randomCode()
            if try await firestore.fetchPairCode(code) == nil {
                let pairCode = PairCode(
                    code: code,
                    creatorUserId: creatorUserId,
                    expiresAt: Date().addingTimeInterval(Constants.pairCodeTTL).timeIntervalSince1970
                )
                try await firestore.createPairCode(pairCode)
                return pairCode
            }
        }
        throw AppError.unknown("生成配对码失败，请重试")
    }

    /// 校验并绑定。返回一个 (myUID, partnerUID) 供上层刷新状态。
    func bind(using code: String, currentUID: String) async throws -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == Constants.pairCodeLength else {
            throw AppError.pairCodeNotFound
        }

        guard let pairCode = try await firestore.fetchPairCode(trimmed) else {
            throw AppError.pairCodeNotFound
        }

        guard !pairCode.isExpired else {
            try? await firestore.deletePairCode(trimmed)
            throw AppError.pairCodeExpired
        }

        guard pairCode.creatorUserId != currentUID else {
            throw AppError.pairCodeSelfUse
        }

        let partnerUID = pairCode.creatorUserId

        // 若双方已互相绑定，幂等返回
        if let me = try await firestore.fetchUser(ownerId: currentUID), me.partnerId == partnerUID {
            try? await firestore.deletePairCode(trimmed)
            throw AppError.alreadyPaired
        }

        try await firestore.bindPartners(uidA: currentUID, uidB: partnerUID)
        try? await firestore.deletePairCode(trimmed)
        return partnerUID
    }

    func unbind(myUID: String, partnerUID: String) async throws {
        try await firestore.unbindPartners(myUID: myUID, partnerUID: partnerUID)
    }

    private static func randomCode() -> String {
        var code = ""
        for _ in 0..<Constants.pairCodeLength {
            code += String(Int.random(in: 0...9))
        }
        return code
    }
}
