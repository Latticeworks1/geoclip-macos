//
//  SettingsView.swift
//  GeoCLIP
//
//  Settings view for GeoCLIP app
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("backend") private var backend = "mlx"
    @AppStorage("defaultTopK") private var defaultTopK = 5

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Inference Backend", selection: $backend) {
                    Text("MLX (Apple Silicon)").tag("mlx")
                    Text("PyTorch").tag("torch")
                }
                .pickerStyle(.radioGroup)

                Text("MLX provides better performance on Apple Silicon Macs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Predictions") {
                Stepper("Default Top-K: \(defaultTopK)", value: $defaultTopK, in: 1...10)

                Text("Number of location predictions to show by default")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GeoCLIP")
                        .font(.headline)

                    Text("Worldwide Image Geo-localization")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Link("GitHub Repository", destination: URL(string: "https://github.com/VicenteVivan/geo-clip")!)
                        .font(.caption)

                    Link("Research Paper (NeurIPS 2023)", destination: URL(string: "https://arxiv.org/abs/2309.16020v2")!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
    }
}

#Preview {
    SettingsView()
}
