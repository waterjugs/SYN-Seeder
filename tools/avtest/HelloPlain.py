"""Antivirus test app: an empty window, packed exactly like SynSeeder.exe."""
import tkinter as tk

root = tk.Tk()
root.title("Hello")
tk.Label(root, text="Hello").pack(padx=40, pady=40)
root.mainloop()
