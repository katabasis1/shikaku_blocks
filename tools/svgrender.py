"""Рендер SVG через librsvg + cairo (ctypes). svg_to_image(svg_bytes, w, h) -> PIL RGBA."""
import ctypes, ctypes.util
from PIL import Image
_rsvg = ctypes.CDLL("librsvg-2.so.2")
_cairo = ctypes.CDLL("libcairo.so.2")
_gobj = ctypes.CDLL("libgobject-2.0.so.0")
class RsvgRectangle(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("width", ctypes.c_double), ("height", ctypes.c_double)]
_rsvg.rsvg_handle_new_from_data.restype = ctypes.c_void_p
_rsvg.rsvg_handle_new_from_data.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p]
_rsvg.rsvg_handle_render_document.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(RsvgRectangle), ctypes.c_void_p]
_cairo.cairo_image_surface_create.restype = ctypes.c_void_p
_cairo.cairo_create.restype = ctypes.c_void_p
_cairo.cairo_create.argtypes = [ctypes.c_void_p]
_cairo.cairo_image_surface_get_data.restype = ctypes.c_void_p
_cairo.cairo_image_surface_get_data.argtypes = [ctypes.c_void_p]
_cairo.cairo_image_surface_get_stride.argtypes = [ctypes.c_void_p]
_cairo.cairo_surface_flush.argtypes = [ctypes.c_void_p]
_cairo.cairo_destroy.argtypes = [ctypes.c_void_p]
_cairo.cairo_surface_destroy.argtypes = [ctypes.c_void_p]
_gobj.g_object_unref.argtypes = [ctypes.c_void_p]

def svg_to_image(data, w, h):
    if isinstance(data, str):
        data = data.encode("utf-8")
    err = ctypes.c_void_p()
    hd = _rsvg.rsvg_handle_new_from_data(data, len(data), ctypes.byref(err))
    if not hd:
        raise RuntimeError("librsvg: не удалось разобрать SVG")
    surf = _cairo.cairo_image_surface_create(0, int(w), int(h))  # ARGB32
    cr = _cairo.cairo_create(surf)
    vp = RsvgRectangle(0, 0, w, h)
    ok = _rsvg.rsvg_handle_render_document(hd, cr, ctypes.byref(vp), ctypes.byref(err))
    _cairo.cairo_surface_flush(surf)
    stride = _cairo.cairo_image_surface_get_stride(surf)
    buf = ctypes.string_at(_cairo.cairo_image_surface_get_data(surf), stride * int(h))
    im = Image.frombuffer("RGBA", (int(w), int(h)), buf, "raw", "BGRa", stride, 1).copy()
    _cairo.cairo_destroy(cr); _cairo.cairo_surface_destroy(surf); _gobj.g_object_unref(hd)
    if not ok:
        raise RuntimeError("librsvg: ошибка рендера")
    return im
