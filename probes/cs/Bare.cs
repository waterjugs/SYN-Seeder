using System;
using System.Windows.Forms;

namespace SynSeeder
{
    /// <summary>The "bare" trial build: only a window, to compare against the full one.</summary>
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            var form = new Form { Text = "SynSeeder", Width = 360, Height = 200 };
            form.Controls.Add(new Label { Text = "SynSeeder", AutoSize = true, Left = 20, Top = 20 });
            var close = new Button { Text = "Close", Left = 20, Top = 60 };
            close.Click += (sender, args) => form.Close();
            form.Controls.Add(close);
            Application.Run(form);
        }
    }
}
