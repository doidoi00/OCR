import SwiftUI
import Vision
import VisionKit
import PDFKit
import UniformTypeIdentifiers
import CoreML
import CoreImage

enum FileType {
    case pdf
    case image
}

struct ContentView: View {
    @State private var ocrResult: String = "여기에 OCR 결과가 표시됩니다"
    @State private var isProcessing: Bool = false
    @State private var progressValue: Double = 0
    @State private var pageImages: [NSImage] = []
    @State private var incorrectTexts: [String] = []
    @State private var correctionMap: [String: String] = [
        "0": "O", "1": "l", "Il": "II", "|I": "II", "5S": "SS", "8B": "BB"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Top button bar
            HStack(spacing: 16) {
                Button("PDF 열기 및 OCR") {
                    startOCR(for: .pdf)
                }
                Button("이미지 열기 및 OCR") {
                    startOCR(for: .image)
                }
                Button("OCR 삭제") {
                    deleteOCR()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Progress bar
            if isProcessing {
                ProgressView(value: progressValue, total: 1.0) {
                    Text("처리 중... \(Int(progressValue * 100))%")
                }
                .padding()
                .progressViewStyle(LinearProgressViewStyle())
            }
            
            // OCR content display
            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(pageImages.indices, id: \.self) { index in
                            Image(nsImage: pageImages[index])
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300)
                                .padding(.bottom, 10)
                                .border(Color.gray.opacity(0.3), width: 1)
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)
                
                ScrollView {
                    TextEditor(text: $ocrResult)
                        .padding()
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                        .frame(minHeight: 300)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Correction suggestions
            if !incorrectTexts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("추천 수정")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(incorrectTexts.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("• \(incorrectTexts[index])")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button("적용") {
                                        self.ocrResult = self.ocrResult.replacingOccurrences(of: incorrectTexts[index], with: recommendedText)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .padding()
    }
    func getRecommendedOCR(for text: String) -> (language: String, text: String) {
        let recommendedLanguage = "ko-KR" // Example: recommending Korean for incorrect text
        let correctedText = performOCR(with: recommendedLanguage, text: text) // OCR in the recommended language
        return (language: recommendedLanguage, text: correctedText)
    }
    
    func performOCR(with language: String, text: String) -> String {
        // Example OCR processing logic for the recommended language
        let ocrResult = "변경된 텍스트" // Replace this with actual OCR result processing
        return ocrResult
    }
    
    func getCorrection(for word: String) -> String {
        var corrected = word
        for (wrong, right) in correctionMap {
            corrected = corrected.replacingOccurrences(of: wrong, with: right)
        }
        return corrected
    }
    
    func detectIncorrectText(in text: String) -> [String] {
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        var detectedIssues: [String] = []
        
        for token in tokens {
            let length = token.count
            
            // 너무 짧거나 너무 긴 단어는 제외
            if length < 2 || length > 30 {
                continue
            }
            
            // 특수문자가 너무 많으면 의심
            let specialCharCount = token.filter { "!@#$%^&*()_+=[]{}|\\:;\"'<>,.?/~`".contains($0) }.count
            if specialCharCount > 2 {
                detectedIssues.append(token)
                continue
            }
            
            // 자주 혼동되는 문자 조합이 포함되어 있으면 의심
            let suspiciousPatterns = ["0O", "1l", "Il", "|I", "5S", "8B"]
            for pattern in suspiciousPatterns {
                if token.contains(pattern) {
                    detectedIssues.append(token)
                    break
                }
            }
            
            // 숫자/영문/한글 섞인 비정상 조합
            let hasNumber = token.range(of: "\\d", options: .regularExpression) != nil
            let hasLetter = token.range(of: "[A-Za-z]", options: .regularExpression) != nil
            let hasHangul = token.range(of: "[가-힣]", options: .regularExpression) != nil
            if (hasNumber && hasHangul) || (hasLetter && hasHangul) {
                detectedIssues.append(token)
            }
        }
        
        return detectedIssues
    }
    
    func displayRecommendedCorrections(incorrectText: [String]) {
        if incorrectText.isEmpty {
            self.ocrResult += "\n\n모든 텍스트가 정확하게 인식되었습니다."
        } else {
            self.ocrResult += "\n\n잘못 인식된 부분:\n"
            for issue in incorrectText {
                self.ocrResult += "- \(issue) (추천 수정: 0 -> O, 1 -> l)\n"
            }
        }
    }
    
    func startOCR(for type: FileType) {
        isProcessing = true
        progressValue = 0
        self.pageImages = []
        let panel = NSOpenPanel()
        switch type {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        case .image:
            panel.allowedContentTypes = [.png, .jpeg, .tiff]
        }
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            if !ocrResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let alert = NSAlert()
                alert.messageText = "기존 OCR 결과가 감지되었습니다."
                alert.informativeText = "기존 결과를 삭제하고 새로 처리하시겠습니까?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "예, 삭제 후 계속")
                alert.addButton(withTitle: "아니오")
                let response = alert.runModal()
                if response != .alertFirstButtonReturn {
                    isProcessing = false
                    return
                }
                ocrResult = ""
            }
            
            if type == .pdf {
                if let pdf = PDFDocument(url: url) {
                    // 0. 텍스트 레이어 유무 확인
                    var extractedText = ""
                    for i in 0..<pdf.pageCount {
                        if let page = pdf.page(at: i),
                           let pageText = page.string,
                           !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            extractedText += pageText
                        }
                    }
                    
                    if !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let alert = NSAlert()
                        alert.messageText = "이 PDF에는 이미 텍스트(OCR 결과)가 포함되어 있습니다."
                        alert.informativeText = "OCR 텍스트를 제거한 후 다시 처리하시겠습니까?"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "예, 제거하고 다시 OCR")
                        alert.addButton(withTitle: "취소")
                        let response = alert.runModal()
                        if response != .alertFirstButtonReturn {
                            self.isProcessing = false
                            return
                        }
                        
#if DEBUG
                        let gsPath = "/opt/homebrew/bin/gs"
                        guard FileManager.default.fileExists(atPath: gsPath) &&
                                FileManager.default.isExecutableFile(atPath: gsPath) else {
                            self.ocrResult = """
                        Ghostscript 실행 파일을 찾을 수 없습니다.
                        터미널에서 아래 명령어로 설치해주세요:
                        brew install ghostscript
                        """
                            self.isProcessing = false
                            return
                        }
                        
                        let task = Process()
                        let cleanURL = url.deletingLastPathComponent().appendingPathComponent("Temp_OCR_Removed.pdf")
                        task.launchPath = gsPath
                        task.arguments = [
                            "-o", cleanURL.path,
                            "-sDEVICE=pdfwrite",
                            "-dFILTERTEXT",
                            url.path
                        ]
                        
                        let pipe = Pipe()
                        task.standardOutput = pipe
                        task.standardError = pipe
                        
                        do {
                            try task.run()
                            task.waitUntilExit()
                            // 재로드
                            if let cleanedPDF = PDFDocument(url: cleanURL) {
                                processPDF(cleanedPDF)
                                return
                            } else {
                                self.ocrResult = "텍스트 제거 후 PDF 로드 실패"
                                self.isProcessing = false
                                return
                            }
                        } catch {
                            self.ocrResult = "Ghostscript 실행 실패: \(error.localizedDescription)"
                            self.isProcessing = false
                            return
                        }
#else
                        self.ocrResult = "App Store용 빌드에서는 OCR 제거 후 재처리 기능이 비활성화되어 있습니다."
                        self.isProcessing = false
                        return
#endif
                    }
                    
                    processPDF(pdf)
                }
            } else if type == .image {
                guard let image = NSImage(contentsOf: url),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    self.ocrResult = "이미지 로드 실패"
                    self.isProcessing = false
                    return
                }
                
                let ciImage = CIImage(cgImage: cgImage)
                    .applyingFilter("CIColorControls", parameters: [
                        kCIInputBrightnessKey: 0.0,
                        kCIInputContrastKey: 1.5,
                        kCIInputSaturationKey: 0.0
                    ])
                let ciContext = CIContext()
                guard let processedCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    self.ocrResult = "이미지 전처리 실패"
                    self.isProcessing = false
                    return
                }
                
                self.pageImages.append(NSImage(cgImage: processedCGImage, size: image.size))
                
                var allText = ""
                let request = VNRecognizeTextRequest { request, error in
                    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                    for observation in observations {
                        if let topCandidate = observation.topCandidates(1).first {
                            allText += topCandidate.string + "\n"
                        }
                    }
                }
                request.revision = VNRecognizeTextRequestRevision3
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let preferred = ["ko-KR", "zh-Hans", "zh-Hant", "ja-JP"]
                let supported: [String]
                if #available(macOS 12.0, *) {
                    supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)) ?? []
                } else {
                    supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)) ?? []
                }
                request.recognitionLanguages = preferred + supported.filter { !preferred.contains($0) }
                
                let handler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
                try? handler.perform([request])
                
                DispatchQueue.main.async {
                    self.ocrResult = allText
                    self.isProcessing = false
                }
            }
        } else {
            self.isProcessing = false
        }
    }
    
    func processPDF(_ pdf: PDFDocument) {
        var allText = ""
        
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            
            // 1. 텍스트 레이어 직접 추출 (OCR 전에 우선 시도)
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += "[페이지 \(i + 1)]\n" + pageText + "\n\n"
                DispatchQueue.main.async {
                    self.progressValue = Double(i + 1) / Double(pdf.pageCount)
                }
                continue
            }
            
            // 2. 이미지 기반 OCR 처리
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let scaledSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: scaledSize)
            image.lockFocus()
            if let cgContext = NSGraphicsContext.current?.cgContext {
                cgContext.interpolationQuality = .high
                cgContext.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: cgContext)
            } else {
                print("❌ NSGraphicsContext.current가 nil입니다! 페이지 \(i + 1)")
                allText += "[페이지 \(i + 1)] 이미지 렌더링 실패\n"
                continue
            }
            image.unlockFocus()
            
            guard let rawCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            
            let ciImage = CIImage(cgImage: rawCGImage)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.0,
                    kCIInputContrastKey: 1.2,
                    kCIInputSaturationKey: 0.0
                ])
            
            let ciContext = CIContext()
            guard let processedCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { continue }
            
            DispatchQueue.main.async {
                self.pageImages.append(NSImage(cgImage: processedCGImage, size: NSSize(width: bounds.width, height: bounds.height)))
            }
            
            let request = VNRecognizeTextRequest { req, error in
                guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        allText += topCandidate.string + "\n"
                    }
                }
            }
            request.revision = VNRecognizeTextRequestRevision3
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let preferred = ["ko-KR", "zh-Hans", "zh-Hant", "ja-JP"]
            let supported: [String]
            if #available(macOS 12.0, *) {
                supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)) ?? []
            } else {
                supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)) ?? []
            }
            request.recognitionLanguages = preferred + supported.filter { !preferred.contains($0) }
            
            let handler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
            try? handler.perform([request])
            
            if allText.isEmpty {
                allText += "[페이지 \(i + 1)] OCR 실패\n"
            }
            
            allText += "\n"
            DispatchQueue.main.async {
                self.progressValue = Double(i + 1) / Double(pdf.pageCount)
            }
        }
        
        DispatchQueue.main.async {
            self.ocrResult = allText
            self.isProcessing = false
        }
    }
    
    func findSuspectWords(in text: String) -> [String] {
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        return tokens.filter { token in
            token.count > 10 || token.range(of: "[^가-힣a-zA-Z0-9]", options: .regularExpression) != nil
        }
    }
    
    func deleteOCR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            guard let pdf = PDFDocument(url: url) else {
                self.ocrResult = "PDF 불러오기 실패"
                return
            }
            
            var extractedText = ""
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    extractedText += pageText
                }
            }
            
            if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.ocrResult = "이 문서에는 OCR 결과가 없는 것으로 보입니다."
            } else {
                let alert = NSAlert()
                alert.messageText = "OCR 결과가 포함된 PDF입니다."
                alert.informativeText = "텍스트 레이어를 제거하시겠습니까? 제거 시 복구할 수 없습니다."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OCR 제거")
                alert.addButton(withTitle: "취소")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
#if DEBUG
                    let gsPath = "/opt/homebrew/bin/gs"
                    guard FileManager.default.fileExists(atPath: gsPath) &&
                            FileManager.default.isExecutableFile(atPath: gsPath) else {
                        self.ocrResult = """
                    Ghostscript 실행 파일을 찾을 수 없습니다.
                    터미널에서 아래 명령어로 설치해주세요:
                    brew install ghostscript
                    """
                        return
                    }
                    
                    let task = Process()
                    task.launchPath = gsPath
                    let outputURL = url.deletingLastPathComponent().appendingPathComponent("OCR_Removed.pdf")
                    task.arguments = [
                        "-o", outputURL.path,
                        "-sDEVICE=pdfwrite",
                        "-dFILTERTEXT",
                        url.path
                    ]
                    
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.standardError = pipe
                    
                    do {
                        try task.run()
                        task.waitUntilExit()
                        self.ocrResult = "Ghostscript를 이용해 OCR 텍스트가 제거된 PDF를 저장했습니다: \(outputURL.lastPathComponent)"
                    } catch {
                        self.ocrResult = "Ghostscript 실행 실패: \(error.localizedDescription)"
                    }
#else
                    self.ocrResult = "App Store용 빌드에서는 Ghostscript 기반 OCR 제거 기능이 비활성화되어 있습니다."
#endif
                } else {
                    self.ocrResult = "OCR 제거가 취소되었습니다."
                }
            }
        }
    }
}
