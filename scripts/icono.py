#!/usr/bin/env python3
"""Genera Mascota.icns. Uso: icono.py <salida.icns>

Si existe ~/.mascota/icono.png (ilustración cuadrada propia, a sangre) le aplica la forma de ícono de
macOS. Si no, usa el cuadro de reposo de la mascota elegida (~/.mascota/mascotas, ~/.codex/pets) o dibuja a Clawd.
"""
import json, pathlib, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter

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

def forma_macos(arte):
    """Cuadrado redondeado de macOS: 824x824 dentro de 1024, radio ~185, con sombra suave."""
    grande = 4                                   # sobremuestreo para bordes suaves
    lado, caja, radio = 1024, 824, 185
    x0 = (lado - caja) // 2
    mascara = Image.new("L", (lado * grande, lado * grande), 0)
    ImageDraw.Draw(mascara).rounded_rectangle(
        [x0 * grande, x0 * grande, (x0 + caja) * grande, (x0 + caja) * grande], radio * grande, fill=255)
    mascara = mascara.resize((lado, lado), Image.LANCZOS)
    arte = arte.convert("RGBA").resize((caja, caja), Image.LANCZOS)
    capa = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    capa.paste(arte, (x0, x0))
    capa.putalpha(mascara)
    sombra = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    sombra.putalpha(mascara.point(lambda a: int(a * 0.35)).filter(ImageFilter.GaussianBlur(14)))
    icono = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    icono.alpha_composite(sombra, (0, 10))
    icono.alpha_composite(capa)
    return icono

def exportar(lienzo, pixel=False):
    iconset = tmp / "Mascota.iconset"
    iconset.mkdir()
    for tam in (16, 32, 128, 256, 512):
        for escala in (1, 2):
            px = tam * escala
            nombre = f"icon_{tam}x{tam}{'@2x' if escala == 2 else ''}.png"
            lienzo.resize((px, px), Image.NEAREST if pixel else Image.LANCZOS).save(iconset / nombre)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(salida)], check=True)

tmp = pathlib.Path(tempfile.mkdtemp())
propio = casa / ".mascota/icono.png"
if propio.exists():
    exportar(forma_macos(Image.open(propio)))
    print("Ícono: ~/.mascota/icono.png")
    sys.exit(0)

ruta = hoja(elegida) or hoja("clawd")
if ruta is None:  # sin mascotas instaladas: dibuja a Clawd
    subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("dibujar-clawd.py")), str(tmp / "clawd")], check=True)
    ruta = tmp / "clawd/spritesheet.png"

celda = Image.open(ruta).convert("RGBA").crop((0, 0, 192, 208))
celda = celda.crop(celda.getbbox() or (0, 0, 192, 208))
lado = int(max(celda.size) * 1.12)                       # un poco de aire alrededor
lienzo = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
lienzo.alpha_composite(celda, ((lado - celda.width) // 2, (lado - celda.height) // 2))
exportar(lienzo, pixel="pixel" in elegida or elegida == "clawd")
print(f"Ícono: {elegida}")
