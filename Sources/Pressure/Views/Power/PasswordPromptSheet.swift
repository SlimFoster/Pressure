import SwiftUI

struct PasswordPromptSheet: View {
    @Binding var isPresented: Bool
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isUnlocking = false

    /// Attempts to unlock with the given password; return `true` on success.
    var onSubmit: (String) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Password")
                .font(.headline)
            Text("This archive is encrypted.")
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { submit() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(isUnlocking ? "Unlocking…" : "Unlock") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isUnlocking)
            }
        }
        .padding(20)
    }

    private func submit() {
        guard !password.isEmpty, !isUnlocking else { return }
        isUnlocking = true
        errorMessage = nil

        Task {
            let success = await onSubmit(password)
            isUnlocking = false
            if success {
                isPresented = false
            } else {
                errorMessage = "Incorrect password"
                password = ""
            }
        }
    }
}
