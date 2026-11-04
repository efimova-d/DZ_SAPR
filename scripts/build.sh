#!/usr/bin/env bash
# =============================================================================
#  Сборка проекта DZ_SAPR (KiCad 10, kicad-cli):
#    1) ERC схемы            -> output/erc.rpt
#    2) DRC платы + соответствие схеме -> output/drc.rpt
#    3) PDF схемы (ч/б)       -> output/DZ_SAPR_schematic.pdf
#    4) BOM (перечень)        -> output/DZ_SAPR_bom.csv
#    5) Gerber + сверловка    -> output/gerbers/, output/DZ_SAPR_gerbers.zip
#    6) 3D-модель STEP        -> output/DZ_SAPR.step
#  Запуск из любой папки:  bash scripts/build.sh
#  Путь к kicad-cli можно задать переменной:  KICAD_CLI=/path/to/kicad-cli bash scripts/build.sh
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."            # корень проекта (все пути дальше — относительные)
PRJ="DZ_SAPR"
OUT="output"
GERB="$OUT/gerbers"

# --- поиск kicad-cli -----------------------------------------------------------
if [ -z "${KICAD_CLI:-}" ]; then
  for c in kicad-cli \
           "/c/Program Files/KiCad/10.0/bin/kicad-cli.exe" \
           "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then KICAD_CLI="$c"; break; fi
  done
fi
if [ -z "${KICAD_CLI:-}" ]; then
  echo "Не найден kicad-cli. Укажите путь: KICAD_CLI=/путь/к/kicad-cli bash scripts/build.sh" >&2
  exit 1
fi

# --- библиотека должна быть получена как сабмодуль -----------------------------
if [ ! -f lib/GOST_ESKD/GOST_ESKD.kicad_sym ]; then
  echo "Нет библиотеки lib/GOST_ESKD. Выполните: git submodule update --init --recursive" >&2
  exit 1
fi

mkdir -p "$GERB"
rm -f "$GERB"/*

echo "==> [1/6] ERC"
if ! "$KICAD_CLI" sch erc --severity-error --exit-code-violations \
      -o "$OUT/erc.rpt" "$PRJ.kicad_sch"; then
  echo "ERC: найдены ошибки, см. $OUT/erc.rpt" >&2; exit 1
fi

echo "==> [2/6] DRC (с проверкой соответствия схеме)"
if ! "$KICAD_CLI" pcb drc --schematic-parity --refill-zones --severity-error --exit-code-violations \
      -o "$OUT/drc.rpt" "$PRJ.kicad_pcb"; then
  echo "DRC: найдены ошибки, см. $OUT/drc.rpt" >&2; exit 1
fi

echo "==> [3/6] PDF схемы"
"$KICAD_CLI" sch export pdf -b -o "$OUT/${PRJ}_schematic.pdf" "$PRJ.kicad_sch"

echo "==> [4/6] BOM"
"$KICAD_CLI" sch export bom \
  --fields 'Reference,Value,Footprint,${QUANTITY},Manufacturer_Part_Number,Manufacturer' \
  --labels 'Reference,Value,Footprint,Qty,Manufacturer_Part_Number,Manufacturer' \
  --group-by 'Value,Footprint,Manufacturer_Part_Number' \
  --exclude-dnp \
  -o "$OUT/${PRJ}_bom.csv" "$PRJ.kicad_sch"

echo "==> [5/6] Gerber и сверловка"
"$KICAD_CLI" pcb export gerbers \
  --layers "F.Cu,B.Cu,F.Paste,B.Paste,F.Mask,B.Mask,F.Silkscreen,B.Silkscreen,Edge.Cuts" \
  -o "$GERB/" "$PRJ.kicad_pcb"
"$KICAD_CLI" pcb export drill --format excellon --excellon-separate-th \
  --generate-map --map-format gerberx2 --drill-origin absolute \
  -o "$GERB/" "$PRJ.kicad_pcb"
if command -v zip >/dev/null 2>&1; then
  (cd "$GERB" && zip -q -r "../${PRJ}_gerbers.zip" .)
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "Compress-Archive -Force -Path '$GERB/*' -DestinationPath '$OUT/${PRJ}_gerbers.zip'"
fi

echo "==> [6/6] STEP"
"$KICAD_CLI" pcb export step --force -o "$OUT/$PRJ.step" "$PRJ.kicad_pcb"

echo "Готово: результаты в папке $OUT/"
