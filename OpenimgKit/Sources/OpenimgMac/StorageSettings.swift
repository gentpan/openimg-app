import SwiftUI
import OpenimgKit

extension AppModel {
    func loadStorageProfiles() async {
        guard connected, let c = try? client() else { return }
        storageProfiles = (try? await c.storageProfiles()) ?? []
    }

    /// 保存(新建或修改)。先探测再落库是服务器的规矩——写不进去的桶比没有
    /// 桶更糟:用户以为配好了,上传才失败。
    func saveStorageProfile(_ input: StorageProfileInput, editing id: String?) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            if let id {
                try await client().updateStorageProfile(id: id, input: input)
            } else {
                try await client().createStorageProfile(input)
            }
            await loadStorageProfiles()
            await loadStats()
            storageCodeSent = false
            announce(L.s.settings.storageSaved)
            return true
        } catch {
            announce(message(error))
            return false
        }
    }

    /// 只探测不保存:同一份表单,服务器拿去戳一下桶就回来,不落库也不要码。
    func testStorageInput(_ input: StorageProfileInput) async {
        busy = true
        defer { busy = false }
        var probe = input
        probe.testOnly = true
        probe.code = ""
        do {
            try await client().createStorageProfile(probe)
            announce(L.s.settings.storageTestPassed)
        } catch {
            announce(message(error))
        }
    }

    func setDefaultStorageProfile(_ p: StorageProfile, code: String) async {
        busy = true
        defer { busy = false }
        do {
            try await client().setDefaultStorageProfile(id: p.id, code: code)
            await loadStorageProfiles()
            storageCodeSent = false
            announce(L.s.settings.storageDefaultSet(p.name))
        } catch {
            announce(message(error))
        }
    }

    func deleteStorageProfile(_ p: StorageProfile, code: String) async {
        busy = true
        defer { busy = false }
        do {
            try await client().deleteStorageProfile(id: p.id, code: code)
            await loadStorageProfiles()
            await loadStats()
            storageCodeSent = false
            announce(L.s.settings.storageRemoved)
        } catch {
            announce(message(error))
        }
    }
}


/// 存储位置表单:新增或编辑一个自有桶。
///
/// 字段与网页端逐一对应(名称/endpoint/区域/桶/前缀/密钥对/公开地址)。密钥
/// 编辑时留空即沿用已存的那把——服务器从不回传密钥。保存要一枚邮箱验证码,
/// 「仅测试」不用:它不改变任何东西。
/// 存储位置:新增或编辑一个自有桶。
///
/// 字段与网页端逐一对应(名称/endpoint/区域/桶/前缀/密钥对/公开地址)。密钥
/// 编辑时留空即沿用已存的那把——服务器从不回传密钥。
///
/// 验证码不在开窗时就发,而是填完点保存才发:这张表单要填一会儿,提前发的
/// 码很可能在填完之前就过期了。
struct StorageProfileForm: View {
    @ObservedObject var model: AppModel
    /// nil 表示新建。
    let editing: StorageProfile?
    let onClose: () -> Void

    @State private var input = StorageProfileInput()
    @State private var code = ""

    private var isEdit: Bool { editing != nil }
    private var ready: Bool {
        !input.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !input.endpoint.trimmingCharacters(in: .whitespaces).isEmpty
            && !input.bucket.trimmingCharacters(in: .whitespaces).isEmpty
            // 新建必须给密钥;编辑留空表示沿用
            && (isEdit || (!input.accessKey.isEmpty && !input.secretKey.isEmpty))
    }

    var body: some View {
        FormSheet(
            title: isEdit ? L.s.settings.storageEditTitle : L.s.settings.storageAddTitle,
            subtitle: model.storageCodeSent && !model.storageCodeSentTo.isEmpty
                ? L.s.settings.codeSentTo(model.storageCodeSentTo)
                : L.s.settings.storagePublicBaseHint,
            width: 460
        ) {
            Field(icon: "textformat") {
                TextField(L.s.settings.storageName, text: $input.name)
            }
            Field(icon: "link") {
                TextField(L.s.settings.storageEndpoint, text: $input.endpoint)
            }
            if let kind = StorageProfileInput.describeEndpoint(input.endpoint) {
                Text(L.s.settings.endpointKind(kind))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Field(icon: "globe") {
                    TextField(L.s.settings.storageRegion, text: $input.region)
                }
                Field(icon: "shippingbox") {
                    TextField(L.s.settings.storageBucket, text: $input.bucket)
                }
            }
            Field(icon: "folder") {
                TextField(L.s.settings.storageKeyPrefix, text: $input.keyPrefix)
            }
            Field(icon: "key") {
                TextField(isEdit ? L.s.settings.storageAccessKeyKeep : L.s.settings.storageAccessKey,
                          text: $input.accessKey)
            }
            Field(icon: "lock") {
                SecureField(isEdit ? L.s.settings.storageSecretKeyKeep : L.s.settings.storageSecretKey,
                            text: $input.secretKey)
            }
            Field(icon: "network") {
                TextField(L.s.settings.storagePublicBase, text: $input.publicBaseURL)
            }

            if model.storageCodeSent {
                Divider().overlay(Color.white.opacity(0.06))
                Field(icon: "number") {
                    TextField(L.s.settings.codeField, text: $code)
                }
            }
        } footer: {
            Button(L.s.settings.storageTest) {
                Task { await model.testStorageInput(input) }
            }
            .buttonStyle(QuietButton())
            .disabled(!ready || model.busy)

            Spacer()

            Button(L.s.settings.cancel) { close() }
                .buttonStyle(QuietButton())
                .keyboardShortcut(.cancelAction)

            if model.storageCodeSent {
                Button(L.s.settings.storageSave) {
                    Task {
                        var payload = input
                        payload.code = code
                        if await model.saveStorageProfile(payload, editing: editing?.id) { close() }
                    }
                }
                .buttonStyle(BrandButton())
                .keyboardShortcut(.defaultAction)
                .disabled(!ready || code.count != 6 || model.busy)
            } else {
                // 先要码:这一步同时也是"表单填完了"的确认。
                Button(L.s.settings.storageSave) {
                    Task { await model.sendCode(.storage) }
                }
                .buttonStyle(BrandButton())
                .keyboardShortcut(.defaultAction)
                .disabled(!ready || model.busy)
            }
        }
        .task {
            guard let e = editing else { return }
            // 密钥不回传,所以两个密钥字段留空 = 沿用。
            var i = StorageProfileInput()
            i.name = e.name; i.endpoint = e.endpoint; i.region = e.region
            i.bucket = e.bucket; i.keyPrefix = e.keyPrefix; i.publicBaseURL = e.publicBaseURL
            input = i
        }
    }

    private func close() {
        model.storageCodeSent = false
        onClose()
    }
}
