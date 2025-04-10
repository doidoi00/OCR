import SwiftUI
import Vision
import PDFKit

enum FileType {
    case pdf
    case image
}

struct ContentView: View {
    @State private var ocrResult: String = ""
    @State private var isProcessing: Bool = false
    @State private var progressValue: Double = 0
    @State private var pageImages: [NSImage] = []
    @State private var showResult: Bool = false
    @State private var currentPDF: PDFDocument? = nil
    @State private var inputPDFPath: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Button("PDF 열기 및 OCR") { startOCR(for: .pdf) }
                Button("이미지 열기 및 OCR") { startOCR(for: .image) }
                Button("OCR 삭제") { deleteOCR(url: URL(fileURLWithPath: "")) }
            }

            if isProcessing {
                ProgressView(value: progressValue) {
                    Text("처리 중... \(Int(progressValue * 100))%")
                }.padding()
            }

            HStack {
                ScrollView {
                    VStack {
                        ForEach(pageImages.indices, id: \.self) { i in
                            Image(nsImage: pageImages[i])
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300)
                        }
                    }.padding()
                }

                if showResult {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $ocrResult)
                            .padding()
                            .font(.body)
                        
                        

                        Button("OCR 텍스트를 PDF에 텍스트 레이어로 추가") {
                            embedOCRTextToPDFAsLayer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
        }.padding()
    }

    func startOCR(for type: FileType) {
        isProcessing = true
        progressValue = 0
        pageImages = []
        showResult = false

        let panel = NSOpenPanel()
        panel.allowedContentTypes = (type == .pdf) ? [.pdf] : [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
        inputPDFPath = url.path  // 선택된 파일 경로 저장

            if type == .pdf, let pdf = PDFDocument(url: url) {
                var extractedText = ""
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i),
                       let pageText = page.string,
                       !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        extractedText += pageText
                    }
                }

                if !extractedText.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "이 PDF에는 이미 텍스트(OCR 결과)가 포함되어 있습니다."
                    alert.informativeText = "OCR 처리를 계속하면 기존 텍스트가 제거됩니다. 계속하시겠습니까?"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "예, OCR 다시 처리")
                    alert.addButton(withTitle: "아니오, 기존 텍스트 보기")

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        if let cleanedPDF = deleteOCR(url: url) {
                            processPDF(cleanedPDF)
                        } else {
                            isProcessing = false
                        }
                    } else {
                        ocrResult = ""
                        for i in 0..<pdf.pageCount {
                            if let page = pdf.page(at: i), let text = page.string {
                                ocrResult += "[페이지 \(i + 1)]\n" + text + "\n\n"
                            }
                        }
                        showResult = true
                        isProcessing = false
                    }
                } else {
                    processPDF(pdf)
                }
            } else if type == .image,
                      let image = NSImage(contentsOf: url),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                performOCR(on: cgImage, size: image.size) { text in
                    DispatchQueue.main.async {
                        self.pageImages.append(image)
                        self.ocrResult = text
                        self.isProcessing = false
                        self.showResult = true
                    }
                }
            } else {
                ocrResult = "파일을 열 수 없습니다."
                isProcessing = false
            }
        } else {
            isProcessing = false
        }
    }

    func processPDF(_ pdf: PDFDocument) {
        let dispatchGroup = DispatchGroup()
        var allText = ""

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }

            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += "[페이지 \(i + 1)]\n" + text + "\n\n"
                continue
            }

            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: size)

            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.interpolationQuality = .high
                context.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context)
            }
            image.unlockFocus()

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

            dispatchGroup.enter()
            performOCR(on: cgImage, size: bounds.size) { text in
                allText += "[페이지 \(i + 1)]\n" + text + "\n\n"
                DispatchQueue.main.async {
                    self.pageImages.append(image)
                    self.progressValue = Double(i + 1) / Double(pdf.pageCount)
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            self.ocrResult = allText
            self.isProcessing = false
            self.showResult = true
        }
        DispatchQueue.main.async {
            self.ocrResult = allText
            self.isProcessing = false
            self.showResult = true
            self.currentPDF = pdf  // OCR 처리가 완료된 PDF를 저장
        }
    }

    func performOCR(on cgImage: CGImage, size: CGSize, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, error in
                var text = ""
                if let results = request.results as? [VNRecognizedTextObservation] {
                    for observation in results {
                        if let top = observation.topCandidates(1).first {
                            text += top.string + "\n"
                        }
                    }
                }
                DispatchQueue.main.async {
                    completion(text)
                }
            }

            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP", "zh-Hans", "zh-Hant"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    func deleteOCR(url: URL) -> PDFDocument? {
#if DEBUG
        let gsPath = "/opt/homebrew/bin/gs"
        guard FileManager.default.isExecutableFile(atPath: gsPath) else {
            ocrResult = "Ghostscript가 설치되어 있지 않습니다.\n'bew install ghostscript' 실행 후 다시 시도하세요."
            return nil
        }

        let outputURL = url.deletingLastPathComponent().appendingPathComponent("OCR_Removed.pdf")
        let task = Process()
        task.launchPath = gsPath
        task.arguments = ["-o", outputURL.path, "-sDEVICE=pdfwrite", "-dFILTERTEXT", url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            if let output = String(data: handle.availableData, encoding: .utf8) {
                print("[DEBUG] Python Output: \(output)")
                if let progress = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    DispatchQueue.main.async {
                        self.progressValue = progress
                    }
                }
            }
        }

        do {
            try task.run()
            task.waitUntilExit()
            return PDFDocument(url: outputURL)
        } catch {
            ocrResult = "Ghostscript 실행 실패: \(error.localizedDescription)"
            return nil
        }
#else
        ocrResult = "릴리즈 빌드에서는 이 기능을 사용할 수 없습니다."
        return nil
#endif
    }

    func embedOCRTextToPDFAsLayer() {
        guard let pdf = currentPDF else {
            ocrResult += "\n\n❌ 처리된 PDF가 없습니다. 먼저 PDF OCR 처리를 진행하세요."
            return
        }

        isProcessing = true
        progressValue = 0.0

        // OCR 결과를 저장할 딕셔너리
        var ocrResults: [String: [[String: Any]]] = [:]

DispatchQueue.global(qos: .userInitiated).async {
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)

            // PDF 페이지를 이미지로 렌더링
            let scale: CGFloat = 2.0
            let imageSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: imageSize)

            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.interpolationQuality = .high
                context.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context)
            }
            image.unlockFocus()

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

            let request = VNRecognizeTextRequest { request, error in
                guard let results = request.results as? [VNRecognizedTextObservation] else { return }

                var pageResults: [[String: Any]] = []

                for observation in results {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let box = observation.boundingBox

                    // Vision의 normalized 좌표를 PDF 좌표로 변환
                    let x = box.origin.x * bounds.width
                    let y = (1 - box.origin.y - box.height) * bounds.height
                    let width = box.width * bounds.width
                    let height = box.height * bounds.height

                    // OCR 결과 저장
                    pageResults.append([
                        "text": candidate.string,
                        "x": x,
                        "y": y,
                        "width": width,
                        "height": height
                    ])
                }

                ocrResults["\(pageIndex)"] = pageResults
            }

            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP", "zh-Hans", "zh-Hant"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        
                // Progress 업데이트
                DispatchQueue.main.async {
                    self.progressValue = Double(pageIndex + 1) / Double(pdf.pageCount)
                }
            }

            DispatchQueue.main.async {
                self.isProcessing = false
                self.progressValue = 1.0
                self.ocrResult += "\n\n✅ OCR 텍스트 레이어가 PDF에 성공적으로 추가되었습니다."
            }

            // Python 스크립트 실행
            runPythonScript()
        }
    }

    func runPythonScript() {
        let pythonScriptPath = "/Users/minyeop-jang/Desktop/PDFOCRApp/PDFOCRApp/View/ocr.py"

        guard let inputPDFPath = inputPDFPath else {
            print("[ERROR] 입력 PDF 파일 경로가 설정되지 않았습니다.")
            return
        }
        
        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.pdf]

            // 이미 guard로 언래핑했으므로 바로 inputPDFPath 사용
            let inputURL = URL(fileURLWithPath: inputPDFPath)
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            savePanel.nameFieldStringValue = "\(baseName)_OCR.pdf"

            guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
                print("[ERROR] 출력 PDF 파일 저장 경로를 설정하지 않았습니다.")
                return
            }

            let outputPDFPath = outputURL.path

            print("[DEBUG] Python Script Path: \(pythonScriptPath)")
            print("[DEBUG] Input PDF Path: \(inputPDFPath)")
            print("[DEBUG] Output PDF Path: \(outputPDFPath)")

            // Python 스크립트 실행
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [pythonScriptPath, inputPDFPath, outputPDFPath]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    if let output = String(data: outputData, encoding: .utf8) {
                        print("[DEBUG] Python Output: \(output)")
                    }
                    if let error = String(data: errorData, encoding: .utf8) {
                        print("[DEBUG] Python Error: \(error)")
                    }

                    if process.terminationStatus == 0 {
                        print("[DEBUG] Python 스크립트 실행 성공")
                    } else {
                        print("[ERROR] Python 스크립트 실행 실패")
                    }
                } catch {
                    print("[ERROR] Python 스크립트 실행 중 오류 발생: \(error.localizedDescription)")
                }
            }
        }
    }
}
