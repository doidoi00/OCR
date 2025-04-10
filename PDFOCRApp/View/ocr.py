import os
import sys
from pdf2image import convert_from_path
from PIL import Image

# Python 실행 경로 출력
print(f"[DEBUG] Python 실행 경로: {sys.executable}")

# Poppler 실행 파일 경로
POPPLER_PATH = "/opt/homebrew/bin"

# 명령줄 인수 처리
print("[DEBUG] 명령줄 인수 처리 시작")
if len(sys.argv) < 3:
    print("[ERROR] 명령줄 인수가 부족합니다. 사용법: python ocr.py <input_pdf> <output_pdf>", file=sys.stderr)
    sys.exit(1)

input_pdf = sys.argv[1]
output_pdf = sys.argv[2]

print(f"[DEBUG] Input PDF Path: {input_pdf}")
print(f"[DEBUG] Output PDF Path: {output_pdf}")

if not os.path.exists(input_pdf):
    print(f"[ERROR] 입력 PDF 파일이 존재하지 않습니다: {input_pdf}", file=sys.stderr)
    sys.exit(1)

# PDF를 이미지로 변환
try:
    print("[DEBUG] PDF를 이미지로 변환 중...")
    images = convert_from_path(input_pdf, poppler_path=POPPLER_PATH)
    print(f"[DEBUG] PDF를 이미지로 변환 완료: {len(images)} 페이지")
except Exception as e:
    print(f"[ERROR] PDF 변환 중 오류 발생: {e}", file=sys.stderr)
    sys.exit(1)

# PDF 저장
try:
    print("[DEBUG] PDF 병합 및 저장 중...")
    images[0].save(output_pdf, save_all=True, append_images=images[1:])
    print(f"[DEBUG] 완료! 저장 위치: {output_pdf}")
except Exception as e:
    print(f"[ERROR] PDF 저장 중 오류 발생: {e}", file=sys.stderr)
    sys.exit(1)