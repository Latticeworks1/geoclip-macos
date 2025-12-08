//
//  ContentView.swift
//  GeoCLIP
//
//  Main view for GeoCLIP native macOS app - Core ML version
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var coreML = GeoCLIPCoreML()
    @State private var predictions: [Prediction] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedImage: NSImage?
    @State private var selectedImagePath: String?
    @State private var topK = 5
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
    )
    @State private var hasShownPredictions = false

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                // Left panel - Image and controls
                leftPanel(availableHeight: geometry.size.height)
                    .frame(minWidth: 320, idealWidth: min(420, geometry.size.width * 0.35), maxWidth: 500)

                // Right panel - Map
                mapPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, idealWidth: 1200, minHeight: 700, idealHeight: 800)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    @ViewBuilder
    private func leftPanel(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                // Header section
                VStack(alignment: .leading, spacing: 12) {
                    Text("GeoCLIP")
                        .font(.system(size: 28, weight: .bold))

                    // Status indicator
                    HStack(spacing: 10) {
                        if !coreML.isReady {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(coreML.statusMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)

                            if !coreML.isReady {
                                Text("Loading models and GPS gallery...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(20)

                Divider()

                // Image section
                VStack(spacing: 12) {
                    let imageHeight = max(200, min(300, availableHeight * 0.3))

                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: imageHeight)
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                        // Image metadata
                        HStack(spacing: 8) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Spacer()

                            if let path = selectedImagePath {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: imageHeight)
                            .overlay(
                                VStack(spacing: 16) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("Drop image or click Select")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                // Controls section
                VStack(spacing: 16) {
                    // Top K selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Results to show")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            ForEach([1, 3, 5, 10], id: \.self) { value in
                                Button(action: {
                                    topK = value
                                }) {
                                    Text("\(value)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(topK == value ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(topK == value ? Color.accentColor : Color.primary.opacity(0.06))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Action buttons
                    VStack(spacing: 10) {
                        Button(action: selectImage) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 14))
                                Text("Select Image")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            if let path = selectedImagePath {
                                predictLocation(imagePath: path)
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "location.magnifyingglass")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                Text(isLoading ? "Analyzing..." : "Predict Location")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedImagePath == nil || isLoading || !coreML.isReady)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)

                Divider()
                    .padding(.top, 16)

                // Predictions section
                VStack(spacing: 0) {
                    HStack {
                        Text("Predictions")
                            .font(.system(size: 16, weight: .semibold))

                        Spacer()

                        if !predictions.isEmpty {
                            Text("\(predictions.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if predictions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: isLoading ? "location.circle" : "location.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(isLoading ? "Analyzing image..." : "No predictions yet")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(predictions) { prediction in
                                    PredictionRow(prediction: prediction) {
                                        withAnimation {
                                            mapRegion.center = CLLocationCoordinate2D(
                                                latitude: prediction.latitude,
                                                longitude: prediction.longitude
                                            )
                                            mapRegion.span = MKCoordinateSpan(
                                                latitudeDelta: 5,
                                                longitudeDelta: 5
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var mapPanel: some View {
        Map(coordinateRegion: $mapRegion, annotationItems: predictions) { prediction in
            MapAnnotation(coordinate: CLLocationCoordinate2D(
                latitude: prediction.latitude,
                longitude: prediction.longitude
            )) {
                PredictionMarker(prediction: prediction)
            }
        }
        .ignoresSafeArea()
    }

    private func predictLocation(imagePath: String) {
        guard coreML.isReady else {
            errorMessage = "Models not ready yet"
            return
        }

        isLoading = true
        predictions = []
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let results = coreML.predict(imagePath: imagePath, topK: topK)

            DispatchQueue.main.async {
                isLoading = false

                if results.isEmpty {
                    errorMessage = "Prediction failed. Check console for details."
                } else {
                    predictions = results
                    errorMessage = nil

                    // Auto-center map on first prediction
                    if !hasShownPredictions || predictions.count > 0 {
                        withAnimation {
                            if let first = predictions.first {
                                mapRegion.center = CLLocationCoordinate2D(
                                    latitude: first.latitude,
                                    longitude: first.longitude
                                )
                                mapRegion.span = MKCoordinateSpan(
                                    latitudeDelta: 20,
                                    longitudeDelta: 20
                                )
                            }
                        }
                        hasShownPredictions = true
                    }
                }
            }
        }
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    private func loadImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            selectedImage = image
            selectedImagePath = url.path
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        loadImage(from: url)
                    }
                }
            }
            return true
        }
        return false
    }
}

struct PredictionRow: View {
    let prediction: Prediction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [rankColor, rankColor.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Text("\(prediction.rank)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.4f°, %.4f°", prediction.latitude, prediction.longitude))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.2f%%", prediction.confidence * 100))
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(rankColor.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(rankColor.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(rankColor.opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var rankColor: Color {
        switch prediction.rank {
        case 1: return .red
        case 2: return .blue
        case 3: return .green
        default: return .purple
        }
    }
}

struct PredictionMarker: View {
    let prediction: Prediction

    var body: some View {
        VStack(spacing: 0) {
            Text("\(prediction.rank)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(markerColor)
                .clipShape(Circle())

            // Pin point
            markerColor
                .frame(width: 2, height: 8)
        }
    }

    private var markerColor: Color {
        switch prediction.rank {
        case 1: return .red
        case 2: return .blue
        case 3: return .green
        default: return .purple
        }
    }
}

#Preview {
    ContentView()
}
