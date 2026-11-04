@echo off
rem ============================================================================
rem  Сборка проекта DZ_SAPR (KiCad 10, kicad-cli) для Windows:
rem    ERC, DRC (+ соответствие схеме), PDF схемы, BOM, Gerber + сверловка, STEP.
rem  Запуск: двойной щелчок по scripts\build.bat или из консоли.
rem  Путь к kicad-cli можно задать заранее:  set KICAD_CLI=C:\...\kicad-cli.exe
rem ============================================================================
chcp 65001 >nul
setlocal

rem --- корень проекта (папка выше scripts), все пути дальше относительные ---
cd /d "%~dp0.."
set "PRJ=DZ_SAPR"
set "OUT=output"
set "GERB=%OUT%\gerbers"

rem --- поиск kicad-cli ---
if not defined KICAD_CLI set "KICAD_CLI=C:\Program Files\KiCad\10.0\bin\kicad-cli.exe"
if not exist "%KICAD_CLI%" set "KICAD_CLI=kicad-cli"

rem --- библиотека должна быть получена как сабмодуль ---
if not exist "lib\GOST_ESKD\GOST_ESKD.kicad_sym" (
  echo Нет библиотеки lib\GOST_ESKD. Выполните: git submodule update --init --recursive
  goto :fail
)

if not exist "%GERB%" mkdir "%GERB%"
del /q "%GERB%\*" 2>nul

echo ==^> [1/6] ERC
"%KICAD_CLI%" sch erc --severity-error --exit-code-violations -o "%OUT%\erc.rpt" "%PRJ%.kicad_sch"
if errorlevel 1 (
  echo ERC: найдены ошибки, см. %OUT%\erc.rpt
  goto :fail
)

echo ==^> [2/6] DRC (с проверкой соответствия схеме)
"%KICAD_CLI%" pcb drc --schematic-parity --refill-zones --severity-error --exit-code-violations -o "%OUT%\drc.rpt" "%PRJ%.kicad_pcb"
if errorlevel 1 (
  echo DRC: найдены ошибки, см. %OUT%\drc.rpt
  goto :fail
)

echo ==^> [3/6] PDF схемы
"%KICAD_CLI%" sch export pdf -b -o "%OUT%\%PRJ%_schematic.pdf" "%PRJ%.kicad_sch"
if errorlevel 1 goto :fail

echo ==^> [4/6] BOM
"%KICAD_CLI%" sch export bom --fields "Reference,Value,Footprint,${QUANTITY},Manufacturer_Part_Number,Manufacturer" --labels "Reference,Value,Footprint,Qty,Manufacturer_Part_Number,Manufacturer" --group-by "Value,Footprint,Manufacturer_Part_Number" --exclude-dnp -o "%OUT%\%PRJ%_bom.csv" "%PRJ%.kicad_sch"
if errorlevel 1 goto :fail

echo ==^> [5/6] Gerber и сверловка
"%KICAD_CLI%" pcb export gerbers --layers "F.Cu,B.Cu,F.Paste,B.Paste,F.Mask,B.Mask,F.Silkscreen,B.Silkscreen,Edge.Cuts" -o "%GERB%\\" "%PRJ%.kicad_pcb"
if errorlevel 1 goto :fail
"%KICAD_CLI%" pcb export drill --format excellon --excellon-separate-th --generate-map --map-format gerberx2 --drill-origin absolute -o "%GERB%\\" "%PRJ%.kicad_pcb"
if errorlevel 1 goto :fail
powershell -NoProfile -Command "Compress-Archive -Force -Path '%GERB%\*' -DestinationPath '%OUT%\%PRJ%_gerbers.zip'"

echo ==^> [6/6] STEP
"%KICAD_CLI%" pcb export step --force -o "%OUT%\%PRJ%.step" "%PRJ%.kicad_pcb"
if errorlevel 1 goto :fail

echo.
echo Готово: результаты в папке %OUT%\
pause
exit /b 0

:fail
echo.
echo СБОРКА ОСТАНОВЛЕНА.
pause
exit /b 1
