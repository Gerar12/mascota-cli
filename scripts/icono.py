#!/usr/bin/env python3
"""Genera Mascota.icns con la mascota elegida (su cuadro de reposo). Uso: icono.py <salida.icns>

Busca la mascota en ~/.mascota/mascotas y ~/.codex/pets; si no hay ninguna, dibuja a Clawd.
"""
import json, pathlib, subprocess, sys, tempfile
from PIL import Image

casa = pathlib.Path.home()
salida = pathlib.Path(sys.argv[1])
elegida = subprocess.run(["defaults", "read", "dev.gcoder.mascota", "mascota"],
                         capture_output=True, text=True).stdout.strip() or "clawd"

def hoja(ident):
    for base in (casa / ".mascota/mascotas", casa / ".codex/pets"):
        for carpeta in base.glob("*") if base.exists() else []:
            try:
                m = json.loads((carpeta / "pet.json").read_text())
            except Exception:
                continue
            if m.get("id") == ident and (carpeta / m["spritesheetPath"]).exists():
                return carpeta / m["spritesheetPath"]
    return None

ruta = hoja(elegida) or hoja("clawd")
tmp = pathlib.Path(tempfile.mkdtemp())
if ruta is None:  # sin mascotas instaladas: dibuja a Clawd
    subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("dibujar-clawd.py")), str(tmp / "clawd")], check=True)
    ruta = tmp / "clawd/spritesheet.png"

celda = Image.open(ruta).convert("RGBA").crop((0, 0, 192, 208))
celda = celda.crop(celda.getbbox() or (0, 0, 192, 208))
lado = int(max(celda.size) * 1.12)                       # un poco de aire alrededor
lienzo = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
lienzo.alpha_composite(celda, ((lado - celda.width) // 2, (lado - celda.height) // 2))
iconset = tmp / "Mascota.iconset"
iconset.mkdir()
pixel = "pixel" in elegida or elegida == "clawd"
for tam in (16, 32, 128, 256, 512):
    for escala in (1, 2):
        px = tam * escala
        filtro = Image.NEAREST if pixel else Image.LANCZOS
        nombre = f"icon_{tam}x{tam}{'@2x' if escala == 2 else ''}.png"
        lienzo.resize((px, px), filtro).save(iconset / nombre)
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(salida)], check=True)
print(f"Ícono: {elegida}")
