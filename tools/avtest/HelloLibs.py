"""Antivirus test app: an empty window that also loads SynSeeder's libraries
(OpenCV, numpy, mss, psutil), packed exactly like SynSeeder.exe."""
import tkinter as tk

import cv2
import mss
import numpy
import psutil

root = tk.Tk()
root.title("Hello")
text = f"OpenCV {cv2.__version__}, numpy {numpy.__version__}, mss {mss.__version__}, psutil {psutil.__version__}"
tk.Label(root, text=text).pack(padx=40, pady=40)
root.mainloop()
