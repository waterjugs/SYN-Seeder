using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace SynSeeder
{
    /// <summary>A grayscale image, one float per pixel, row by row.</summary>
    sealed class Gray
    {
        public readonly int Width, Height;
        public readonly float[] Pixels;

        public Gray(int width, int height)
        {
            Width = width;
            Height = height;
            Pixels = new float[width * height];
        }

        public float this[int x, int y] => Pixels[y * Width + x];

        public static Gray FromBitmap(Bitmap bitmap)
        {
            var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                var gray = new Gray(bitmap.Width, bitmap.Height);
                var row = new byte[gray.Width * 4];
                for (int y = 0; y < gray.Height; y++)
                {
                    Marshal.Copy(data.Scan0 + y * data.Stride, row, 0, row.Length);
                    for (int x = 0, o = y * gray.Width; x < gray.Width; x++)
                    {
                        int b = row[x * 4], g = row[x * 4 + 1], r = row[x * 4 + 2];
                        gray.Pixels[o + x] = (r * 4899 + g * 9617 + b * 1868 + 8192) >> 14;  // as OpenCV's BGR2GRAY
                    }
                }
                return gray;
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
        }

        public Gray Crop(Rectangle area)
        {
            var result = new Gray(area.Width, area.Height);
            for (int y = 0; y < area.Height; y++)
                Array.Copy(Pixels, (area.Top + y) * Width + area.Left, result.Pixels, y * area.Width, area.Width);
            return result;
        }

        /// <summary>Resizes by averaging the source area under each new pixel (OpenCV's INTER_AREA when shrinking).</summary>
        public Gray Resize(int width, int height)
        {
            if (width == Width && height == Height)
                return this;
            var columns = Weights(Width, width);
            var rows = Weights(Height, height);
            var across = new float[width * Height];
            for (int y = 0; y < Height; y++)
                for (int x = 0; x < width; x++)
                {
                    float sum = 0;
                    foreach (var (index, weight) in columns[x])
                        sum += Pixels[y * Width + index] * weight;
                    across[y * width + x] = sum;
                }
            var result = new Gray(width, height);
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                {
                    float sum = 0;
                    foreach (var (index, weight) in rows[y])
                        sum += across[index * width + x] * weight;
                    result.Pixels[y * width + x] = (float)Math.Round(sum);
                }
            return result;
        }

        static (int, float)[][] Weights(int from, int to)
        {
            double scale = (double)from / to;
            var result = new (int, float)[to][];
            for (int i = 0; i < to; i++)
            {
                double start = i * scale, end = start + Math.Max(scale, 1);
                if (scale < 1)  // growing: blend the two nearest pixels
                {
                    double centre = (i + 0.5) * scale - 0.5;
                    int left = Math.Max(0, (int)Math.Floor(centre)), right = Math.Min(from - 1, left + 1);
                    float t = (float)Math.Max(0, Math.Min(1, centre - left));
                    result[i] = new[] { (left, 1 - t), (right, t) };
                    continue;
                }
                var parts = new List<(int, float)>();
                for (int s = (int)Math.Floor(start); s < Math.Min(from, (int)Math.Ceiling(end)); s++)
                {
                    double overlap = Math.Min(end, s + 1) - Math.Max(start, s);
                    if (overlap > 1e-9)
                        parts.Add((s, (float)(overlap / scale)));
                }
                result[i] = parts.ToArray();
            }
            return result;
        }

        /// <summary>A light 3x3 Gaussian blur, edges mirrored like OpenCV's default.</summary>
        public Gray Blur3()
        {
            var across = new float[Pixels.Length];
            for (int y = 0; y < Height; y++)
                for (int x = 0; x < Width; x++)
                {
                    int l = x > 0 ? x - 1 : Math.Min(1, Width - 1), r = x < Width - 1 ? x + 1 : Math.Max(0, Width - 2);
                    across[y * Width + x] = 0.25f * Pixels[y * Width + l] + 0.5f * Pixels[y * Width + x] + 0.25f * Pixels[y * Width + r];
                }
            var result = new Gray(Width, Height);
            for (int y = 0; y < Height; y++)
            {
                int u = y > 0 ? y - 1 : Math.Min(1, Height - 1), d = y < Height - 1 ? y + 1 : Math.Max(0, Height - 2);
                for (int x = 0; x < Width; x++)
                    result.Pixels[y * Width + x] = (float)Math.Round(0.25f * across[u * Width + x] + 0.5f * across[y * Width + x] + 0.25f * across[d * Width + x]);
            }
            return result;
        }
    }

    /// <summary>A template prepared for one scale, with what the score formula needs precomputed.</summary>
    sealed class Needle
    {
        public readonly Gray Image;
        public readonly float[] Centred;  // pixels minus their mean
        public readonly double Energy;    // sum of Centred squared
        public readonly Needle Coarse;    // a smaller copy for the first, rough pass, or null
        public readonly int Factor;       // how much smaller Coarse is: 4, 2 or 1 (no rough pass)

        public Needle(Gray image, bool coarse = true)
        {
            Image = image;
            double mean = image.Pixels.Average();
            Centred = image.Pixels.Select(p => (float)(p - mean)).ToArray();
            Energy = Centred.Sum(p => (double)p * p);
            Factor = 1;
            if (!coarse)
                return;
            foreach (int factor in new[] { 4, 2 })
                if (image.Width / factor >= 6 && image.Height / factor >= 6)
                {
                    Factor = factor;
                    Coarse = new Needle(image.Resize(image.Width / factor, image.Height / factor), false);
                    break;
                }
        }
    }

    struct Hit
    {
        public int X, Y;  // centre, in working-frame pixels
        public double Score;
    }

    /// <summary>
    /// Finds buttons by normalised cross-correlation (OpenCV's TM_CCOEFF_NORMED), the same way the Python
    /// version does: frames shrink to 720 pixels high and get a light blur, and templates cut from 1440p
    /// screenshots are prepared the same way at three scales. A rough pass on a smaller copy finds candidates,
    /// and exact scores are worked out around them.
    /// </summary>
    sealed class Vision
    {
        public const int TemplateHeight = 1440, WorkHeight = 720;
        public const double MatchThreshold = 0.88;
        static readonly double[] Scales = { 0.95, 1.0, 1.05 };
        static readonly Dictionary<string, double> Thresholds = new Dictionary<string, double>
        {
            ["browser_join"] = 0.84,
            ["server_row"] = 0.84,
            ["create_unit"] = 0.80,
        };
        public static readonly string[] Required =
        {
            "admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "switch_team", "server_row",
            "browser_search", "browser_refresh", "menu_enlist", "browser_join", "faction_nva",
            "infantry_create", "select_force", "force_us", "force_nva", "create_unit", "create_unit_button",
        };
        static readonly Regex HeightVariant = new Regex(@"^(\d{3,4})p$");

        readonly Dictionary<string, List<Needle>> needles = new Dictionary<string, List<Needle>>();
        Gray frame;
        Point origin;
        double factor = 1;

        public Vision(Dictionary<string, List<(Gray image, int cutAt)>> templates)
        {
            foreach (var pair in templates)
                needles[pair.Key] = pair.Value
                    .SelectMany(t => Scales.Select(s => Prepare(t.image, (double)WorkHeight / t.cutAt * s)))
                    .ToList();
        }

        public IEnumerable<string> Names => needles.Keys;

        static Needle Prepare(Gray image, double scale)
        {
            int width = Math.Max(1, (int)Math.Round(image.Width * scale)), height = Math.Max(1, (int)Math.Round(image.Height * scale));
            return new Needle(image.Resize(width, height).Blur3());
        }

        /// <summary>Templates built into the exe, then any the player put in %APPDATA%\SynSeeder\templates.</summary>
        public static Dictionary<string, List<(Gray, int)>> LoadTemplates()
        {
            var templates = new Dictionary<string, List<(Gray, int)>>();
            var assembly = Assembly.GetExecutingAssembly();
            foreach (string resource in assembly.GetManifestResourceNames().Where(r => r.StartsWith("templates/") && r.EndsWith(".png")).OrderBy(r => r))
                using (var stream = assembly.GetManifestResourceStream(resource))
                using (var bitmap = new Bitmap(stream))
                    Add(templates, null, Path.GetFileNameWithoutExtension(resource.Substring("templates/".Length)), Gray.FromBitmap(bitmap));
            string folder = Path.Combine(Config.Folder, "templates");
            if (Directory.Exists(folder))
            {
                var overridden = new HashSet<string>();
                foreach (string file in Directory.GetFiles(folder, "*.png").OrderBy(f => f))
                    try
                    {
                        using (var bitmap = new Bitmap(file))
                            Add(templates, overridden, Path.GetFileNameWithoutExtension(file), Gray.FromBitmap(bitmap));
                    }
                    catch (ArgumentException)
                    {
                        Log.Write("Skipped " + file + ": not a readable PNG");
                    }
            }
            return templates;
        }

        static void Add(Dictionary<string, List<(Gray, int)>> templates, HashSet<string> overridden, string stem, Gray image)
        {
            string[] parts = stem.Split('.');
            string name = parts[0];
            var height = parts.Length > 1 ? HeightVariant.Match(parts[parts.Length - 1]) : Match.Empty;
            int cutAt = height.Success ? int.Parse(height.Groups[1].Value) : TemplateHeight;
            if (overridden != null && overridden.Add(name) || !templates.ContainsKey(name))
                templates[name] = new List<(Gray, int)>();
            templates[name].Add((image, cutAt));
        }

        /// <summary>Uses a new screenshot; area is where it came from on screen.</summary>
        public void SetFrame(Gray screenshot, Rectangle area)
        {
            int width = (int)Math.Round(screenshot.Width * (double)WorkHeight / screenshot.Height);
            frame = screenshot.Resize(width, WorkHeight).Blur3();
            origin = area.Location;
            factor = (double)screenshot.Height / WorkHeight;
        }

        /// <summary>Takes a screenshot of part of the screen, in real pixels.</summary>
        public static Gray Capture(Rectangle area)
        {
            using (var bitmap = new Bitmap(area.Width, area.Height, PixelFormat.Format32bppArgb))
            {
                using (var graphics = Graphics.FromImage(bitmap))
                    graphics.CopyFromScreen(area.Left, area.Top, 0, 0, area.Size, CopyPixelOperation.SourceCopy);
                return Gray.FromBitmap(bitmap);
            }
        }

        /// <summary>The on-screen centre of the best match, or null.</summary>
        public Point? Find(string name, RectangleF? region = null)
        {
            var hits = Hits(name, region);
            return hits.Count > 0 ? ToScreen(hits[0]) : (Point?)null;
        }

        public List<Point> FindAll(string name, RectangleF? region = null) => Hits(name, region).Select(ToScreen).ToList();

        Point ToScreen(Hit hit) => new Point(origin.X + (int)Math.Round(hit.X * factor), origin.Y + (int)Math.Round(hit.Y * factor));

        public List<Hit> Hits(string name, RectangleF? region = null)
        {
            if (frame == null || !needles.TryGetValue(name, out var list))
                return new List<Hit>();
            double threshold = Thresholds.TryGetValue(name, out double t) ? t : MatchThreshold;
            return MatchAll(frame, list, region, threshold);
        }

        /// <summary>A region of the game's 16:9 menu area, which wider screens keep in the middle.</summary>
        public static Rectangle MenuRegion(RectangleF region, int width, int height)
        {
            double share = 16.0 / 9 * height / width, left = region.Left, right = region.Right;
            if (share < 1)
            {
                double side = (1 - share) / 2;
                left = side + left * share;
                right = side + right * share;
            }
            return Rectangle.FromLTRB((int)(left * width), (int)(region.Top * height), (int)(right * width), (int)(region.Bottom * height));
        }

        public static List<Hit> MatchAll(Gray frame, List<Needle> needles, RectangleF? region, double threshold)
        {
            Rectangle area = region.HasValue ? MenuRegion(region.Value, frame.Width, frame.Height) : new Rectangle(0, 0, frame.Width, frame.Height);
            Gray part = region.HasValue ? frame.Crop(area) : frame;
            var smaller = new Dictionary<int, Gray>();  // the frame at each rough-pass size, made when first needed
            Gray Small(int factor) => smaller.TryGetValue(factor, out var image) ? image
                : smaller[factor] = part.Resize(part.Width / factor, part.Height / factor);
            var hits = new List<(Hit hit, int w, int h)>();
            foreach (var needle in needles)
            {
                int w = needle.Image.Width, h = needle.Image.Height;
                if (w > part.Width || h > part.Height)
                    continue;
                foreach (var (x, y, score) in Search(part, needle, Small, threshold))
                    hits.Add((new Hit { X = area.Left + x + w / 2, Y = area.Top + y + h / 2, Score = score }, w, h));
            }
            var kept = new List<(Hit hit, int w, int h)>();
            foreach (var candidate in hits.OrderByDescending(c => c.hit.Score))
                if (kept.All(k => Math.Abs(candidate.hit.X - k.hit.X) > k.w / 2 || Math.Abs(candidate.hit.Y - k.hit.Y) > k.h / 2))
                    kept.Add(candidate);
            return kept.Select(k => k.hit).ToList();
        }

        /// <summary>Top-left corners scoring at least the threshold.</summary>
        static List<(int, int, double)> Search(Gray image, Needle needle, Func<int, Gray> smaller, double threshold)
        {
            var sums = new Integral(image);
            int maxX = image.Width - needle.Image.Width, maxY = image.Height - needle.Image.Height;
            var found = new List<(int, int, double)>();
            if (needle.Coarse == null || (long)(maxX + 1) * (maxY + 1) * needle.Centred.Length < 20_000_000)
            {
                Scan(image, sums, needle, 0, 0, maxX, maxY, threshold, found);
                return found;
            }
            // Rough pass on a smaller copy: keep the best separate peaks, then score around each one exactly.
            int f = needle.Factor;
            var small = smaller(f);
            var coarse = new List<(int, int, double)>();
            Scan(small, new Integral(small), needle.Coarse, 0, 0,
                 small.Width - needle.Coarse.Image.Width, small.Height - needle.Coarse.Image.Height,
                 Math.Max(0.3, threshold - 0.35), coarse);
            var peaks = new List<(int, int, double)>();
            int apartX = Math.Max(1, needle.Coarse.Image.Width / 2), apartY = Math.Max(1, needle.Coarse.Image.Height / 2);
            foreach (var peak in coarse.OrderByDescending(c => c.Item3))
            {
                if (peaks.Count == 32)
                    break;
                if (peaks.All(p => Math.Abs(p.Item1 - peak.Item1) > apartX || Math.Abs(p.Item2 - peak.Item2) > apartY))
                    peaks.Add(peak);
            }
            var seen = new HashSet<long>();
            foreach (var (cx, cy, _) in peaks)
            {
                int x0 = Math.Max(0, cx * f - f), y0 = Math.Max(0, cy * f - f);
                int x1 = Math.Min(maxX, cx * f + f), y1 = Math.Min(maxY, cy * f + f);
                var local = new List<(int, int, double)>();
                Scan(image, sums, needle, x0, y0, x1, y1, threshold, local);
                foreach (var hit in local)
                    if (seen.Add((long)hit.Item2 * 100000 + hit.Item1))
                        found.Add(hit);
            }
            return found;
        }

        static void Scan(Gray image, Integral sums, Needle needle, int x0, int y0, int x1, int y1, double threshold, List<(int, int, double)> found)
        {
            int w = needle.Image.Width, h = needle.Image.Height, n = w * h, stride = image.Width;
            float[] pixels = image.Pixels, centred = needle.Centred;
            var gate = new object();
            Parallel.For(y0, y1 + 1, y =>
            {
                List<(int, int, double)> row = null;
                for (int x = x0; x <= x1; x++)
                {
                    double windowSum = sums.Sum(x, y, w, h), windowSquares = sums.Squares(x, y, w, h);
                    double variance = windowSquares - windowSum * windowSum / n;
                    if (variance <= 1e-6 || needle.Energy <= 1e-6)
                        continue;
                    double dot = 0;
                    for (int j = 0, k = 0; j < h; j++)
                    {
                        int at = (y + j) * stride + x;
                        for (int i = 0; i < w; i++, k++)
                            dot += centred[k] * pixels[at + i];
                    }
                    double score = dot / Math.Sqrt(variance * needle.Energy);
                    if (score >= threshold)
                        (row ?? (row = new List<(int, int, double)>())).Add((x, y, score));
                }
                if (row != null)
                    lock (gate)
                        found.AddRange(row);
            });
        }

        /// <summary>Running sums, so any window's sum and sum of squares take four lookups.</summary>
        sealed class Integral
        {
            readonly int stride;
            readonly double[] sum, squares;

            public Integral(Gray image)
            {
                stride = image.Width + 1;
                sum = new double[stride * (image.Height + 1)];
                squares = new double[sum.Length];
                for (int y = 0; y < image.Height; y++)
                {
                    double rowSum = 0, rowSquares = 0;
                    for (int x = 0; x < image.Width; x++)
                    {
                        double p = image.Pixels[y * image.Width + x];
                        rowSum += p;
                        rowSquares += p * p;
                        sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] + rowSum;
                        squares[(y + 1) * stride + x + 1] = squares[y * stride + x + 1] + rowSquares;
                    }
                }
            }

            public double Sum(int x, int y, int w, int h) => Box(sum, x, y, w, h);

            public double Squares(int x, int y, int w, int h) => Box(squares, x, y, w, h);

            double Box(double[] table, int x, int y, int w, int h) =>
                table[(y + h) * stride + x + w] - table[y * stride + x + w] - table[(y + h) * stride + x] + table[y * stride + x];
        }
    }
}
