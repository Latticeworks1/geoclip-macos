//
//  GeoCLIPCoreML.swift
//  GeoCLIP
//
//  Pure Swift Core ML inference - no Python needed
//

import Foundation
import CoreML
import Vision
import AppKit

struct Prediction: Codable, Identifiable {
    let id = UUID()
    let rank: Int
    let latitude: Double
    let longitude: Double
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case rank, latitude, longitude, confidence
    }
}

class GeoCLIPCoreML: ObservableObject {
    @Published var isReady = false
    @Published var statusMessage = "Initializing..."

    private var imageEncoder: MLModel?
    private var locationEncoder: MLModel?
    private var gpsGallery: [(lat: Float, lon: Float)] = []
    private var galleryFeatures: [Float] = []

    private let featureDim = 512
    private let gallerySize = 100000
    private let loadingQueue = DispatchQueue(label: "com.geoclip.loading", qos: .userInitiated)
    private var modelsLoaded = false
    private var galleryLoaded = false
    private var normalizedGalleryFeatures: [Float] = []

    init() {
        // Load models on background thread to avoid UI blocking
        loadingQueue.async { [weak self] in
            self?.loadModels()
            self?.loadGalleryFeatures()
            self?.checkReady()
        }
    }

    private func checkReady() {
        if modelsLoaded && galleryLoaded {
            DispatchQueue.main.async {
                self.isReady = true
                self.statusMessage = "Ready"
                print("=== GeoCLIP Ready ===")
            }
        }
    }

    private func loadModels() {
        do {
            // Load Core ML models from app bundle
            guard let imageModelURL = Bundle.main.url(forResource: "ImageEncoder", withExtension: "mlpackage"),
                  let locationModelURL = Bundle.main.url(forResource: "LocationEncoder", withExtension: "mlpackage") else {
                print("Error: Core ML models not found in bundle")
                return
            }

            print("Compiling models...")

            // Compile models first
            let compiledImageURL = try MLModel.compileModel(at: imageModelURL)
            let compiledLocationURL = try MLModel.compileModel(at: locationModelURL)

            print("Models compiled successfully")
            print("  Image: \(compiledImageURL.path)")
            print("  Location: \(compiledLocationURL.path)")

            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            imageEncoder = try MLModel(contentsOf: compiledImageURL, configuration: config)
            locationEncoder = try MLModel(contentsOf: compiledLocationURL, configuration: config)

            modelsLoaded = true
            print("Core ML models loaded successfully")
        } catch {
            print("Failed to load Core ML models: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Model loading failed"
            }
        }
    }

    private func loadGalleryFeatures() {
        do {
            guard let binURL = Bundle.main.url(forResource: "gps_gallery_features", withExtension: "bin") else {
                print("Error: gps_gallery_features.bin not found")
                return
            }

            let data = try Data(contentsOf: binURL)

            // Read gallery size (4 bytes)
            let size = data.withUnsafeBytes { $0.load(as: Int32.self) }
            guard size == gallerySize else {
                print("Error: Gallery size mismatch")
                return
            }

            // Read GPS coordinates (8 bytes each = 2 floats)
            var offset = 4
            for _ in 0..<gallerySize {
                let lat = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float32.self) }
                let lon = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: Float32.self) }
                gpsGallery.append((lat: lat, lon: lon))
                offset += 8
            }

            // Read pre-computed features (512 floats per location)
            _ = gallerySize * featureDim * 4  // Calculated for documentation
            galleryFeatures = data.withUnsafeBytes { bytes in
                let ptr = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float32.self)
                return Array(UnsafeBufferPointer(start: ptr, count: gallerySize * featureDim))
            }

            // Pre-normalize all gallery features for fast cosine similarity
            print("Normalizing gallery features...")
            normalizedGalleryFeatures = [Float](repeating: 0, count: gallerySize * featureDim)
            for i in 0..<gallerySize {
                var normSq: Float = 0
                for j in 0..<featureDim {
                    let val = galleryFeatures[i * featureDim + j]
                    normSq += val * val
                }
                let norm = sqrt(normSq)
                for j in 0..<featureDim {
                    normalizedGalleryFeatures[i * featureDim + j] = galleryFeatures[i * featureDim + j] / norm
                }
            }

            galleryLoaded = true
            print("Loaded gallery: \(gallerySize) locations with normalized features")
        } catch {
            print("Failed to load gallery features: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Gallery loading failed"
            }
        }
    }

    func predict(imagePath: String, topK: Int = 5) -> [Prediction] {
        let startTime = Date()
        print("=== Starting prediction ===")
        print("Image path: \(imagePath)")
        print("Top K: \(topK)")
        print("Models loaded: \(modelsLoaded), Gallery loaded: \(galleryLoaded)")
        print("Timestamp: \(startTime)")

        guard isReady else {
            print("ERROR: GeoCLIP not ready yet")
            return []
        }

        guard let imageEncoder = imageEncoder else {
            print("ERROR: Image encoder not loaded")
            return []
        }

        guard !galleryFeatures.isEmpty else {
            print("ERROR: Gallery features empty")
            return []
        }

        print("Models loaded, gallery size: \(gpsGallery.count)")

        do {
            // Load and preprocess image
            print("Loading image...")
            guard let image = NSImage(contentsOfFile: imagePath) else {
                print("ERROR: Failed to load image from path")
                return []
            }
            print("Image loaded: \(image.size)")

            print("Encoding image...")
            let encodeStart = Date()
            let imageFeatures = try encodeImage(image, using: imageEncoder)
            let encodeTime = Date().timeIntervalSince(encodeStart)
            let featNorm = sqrt(imageFeatures.map { $0 * $0 }.reduce(0, +))
            print("  Encoded in \(String(format: "%.3f", encodeTime))s")
            print("  Feature count: \(imageFeatures.count)")
            print("  Feature norm: \(String(format: "%.3f", featNorm))")
            print("  Sample values: [\(imageFeatures.prefix(5).map { String(format: "%.3f", $0) }.joined(separator: ", "))]")

            // Compute similarities with gallery
            print("Computing similarities with \(gallerySize) locations...")
            let simStart = Date()
            let similarities = computeSimilarities(imageFeatures: imageFeatures)
            let simTime = Date().timeIntervalSince(simStart)
            print("  Computed in \(String(format: "%.3f", simTime))s")
            print("  Max similarity: \(String(format: "%.6f", similarities.max() ?? 0))")
            print("  Min similarity: \(String(format: "%.6f", similarities.min() ?? 0))")

            // Get top K
            print("Getting top K...")
            let topIndices = getTopK(from: similarities, k: topK)
            print("Top indices: \(topIndices)")

            // Build predictions
            let predictions = topIndices.enumerated().map { index, galleryIdx in
                let gps = gpsGallery[galleryIdx]
                return Prediction(
                    rank: index + 1,
                    latitude: Double(gps.lat),
                    longitude: Double(gps.lon),
                    confidence: Double(max(0, similarities[galleryIdx]))
                )
            }

            let elapsed = Date().timeIntervalSince(startTime)
            print("=== Prediction complete ===")
            print("  Results: \(predictions.count)")
            print("  Time: \(String(format: "%.2f", elapsed))s")
            print("  Top prediction: \(predictions.first?.latitude ?? 0), \(predictions.first?.longitude ?? 0)")
            return predictions
        } catch {
            print("ERROR: Prediction failed: \(error)")
            print("Error details: \(error.localizedDescription)")
            return []
        }
    }

    private func encodeImage(_ image: NSImage, using model: MLModel) throws -> [Float] {
        // Convert NSImage to normalized tensor [1, 3, 224, 224]
        guard let inputArray = image.toNormalizedTensor() else {
            throw NSError(domain: "GeoCLIP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create tensor"])
        }

        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: ["image_input": inputArray])
        let output = try model.prediction(from: input)

        // Extract features (output is 512-dim vector)
        guard let features = output.featureValue(for: "var_2059")?.multiArrayValue else {
            throw NSError(domain: "GeoCLIP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid output"])
        }

        return features.toFloatArray()
    }

    private func computeSimilarities(imageFeatures: [Float]) -> [Float] {
        // Normalize image features
        let imageNorm = sqrt(imageFeatures.map { $0 * $0 }.reduce(0, +))
        let normalizedImage = imageFeatures.map { $0 / imageNorm }

        // Compute cosine similarity with pre-normalized gallery features.
        // Raw dot product of two unit vectors is the cosine similarity in [-1, 1].
        // Softmax is omitted: it is monotone so ranking is identical, but it
        // collapses all 100k probabilities to ~1e-5, making the % display useless.
        var similarities = [Float](repeating: 0, count: gallerySize)
        for i in 0..<gallerySize {
            var dot: Float = 0
            for j in 0..<featureDim {
                dot += normalizedImage[j] * normalizedGalleryFeatures[i * featureDim + j]
            }
            similarities[i] = dot
        }
        return similarities
    }

    private func getTopK(from array: [Float], k: Int) -> [Int] {
        return array.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(k)
            .map { $0.offset }
    }
}

// Helper extensions
extension NSImage {
    func toNormalizedTensor() -> MLMultiArray? {
        // Resize to 224x224
        guard let resized = self.resized(to: CGSize(width: 224, height: 224)) else {
            return nil
        }

        guard let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Create bitmap context to get pixel data
        let width = 224
        let height = 224
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Create MLMultiArray with shape [1, 3, 224, 224]
        guard let array = try? MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32) else {
            return nil
        }

        // CLIP normalization constants
        let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
        let std: [Float] = [0.26862954, 0.26130258, 0.27577711]

        // Convert pixels to normalized tensor in NCHW format
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel

                let r = Float(pixelData[pixelIndex]) / 255.0
                let g = Float(pixelData[pixelIndex + 1]) / 255.0
                let b = Float(pixelData[pixelIndex + 2]) / 255.0

                // Normalize and store in NCHW format
                let baseIndex = y * width + x
                array[baseIndex] = NSNumber(value: (r - mean[0]) / std[0])  // R channel
                array[width * height + baseIndex] = NSNumber(value: (g - mean[1]) / std[1])  // G channel
                array[2 * width * height + baseIndex] = NSNumber(value: (b - mean[2]) / std[2])  // B channel
            }
        }

        return array
    }

    func resized(to targetSize: CGSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }

        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high

        self.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )

        return newImage
    }
}

extension MLMultiArray {
    func toFloatArray() -> [Float] {
        var array = [Float](repeating: 0, count: self.count)
        for i in 0..<self.count {
            array[i] = Float(truncating: self[i])
        }
        return array
    }
}
