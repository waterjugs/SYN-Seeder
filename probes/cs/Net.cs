using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace SynSeeder
{
    /// <summary>The only two places SynSeeder talks to: the server's stats page and GitHub.</summary>
    static class Net
    {
        public static readonly HttpClient Client = MakeClient();

        static HttpClient MakeClient()
        {
            var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("SynSeeder", Program.Version));
            client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("(+https://github.com/waterjugs/SYN-Seeder)"));
            return client;
        }

        public static async Task<Dictionary<string, object>> GetJsonAsync(string url, string accept = "application/json")
        {
            using (var request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.Accept.ParseAdd(accept);
                using (var response = await Client.SendAsync(request).ConfigureAwait(false))
                {
                    response.EnsureSuccessStatusCode();
                    string text = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    return new JavaScriptSerializer().DeserializeObject(text) as Dictionary<string, object>;
                }
            }
        }
    }

    sealed class ServerStatus
    {
        public string Name;
        public int Players;
        public int Allied;
        public int Axis;

        /// <summary>The team to join: the one with fewer players, allies on a tie.</summary>
        public string WeakerSide => Allied <= Axis ? "allies" : "axis";
    }

    static class Stats
    {
        /// <summary>The server's population from its CRCON public info page, or null when it can't be read.</summary>
        public static async Task<ServerStatus> FetchAsync(string url)
        {
            try
            {
                var payload = await Net.GetJsonAsync(url).ConfigureAwait(false);
                return Parse(payload);
            }
            catch (Exception error) when (error is HttpRequestException || error is TaskCanceledException
                                          || error is ArgumentException || error is InvalidOperationException
                                          || error is InvalidCastException || error is KeyNotFoundException)
            {
                Log.Write("Couldn't read the server's player count from " + url + ": " + error.Message);
                return null;
            }
        }

        public static ServerStatus Parse(Dictionary<string, object> payload)
        {
            if (payload == null || (payload.TryGetValue("failed", out object failed) && failed is bool f && f)
                || !(payload.TryGetValue("result", out object value) && value is Dictionary<string, object> result))
                throw new InvalidOperationException("the stats page reported a failure");
            var teams = result.TryGetValue("player_count_by_team", out object t) ? t as Dictionary<string, object> : null;
            string name = "";
            if (result.TryGetValue("name", out object n))
                name = n is Dictionary<string, object> named && named.TryGetValue("name", out object inner) ? Convert.ToString(inner) : Convert.ToString(n);
            return new ServerStatus
            {
                Name = name,
                Players = Convert.ToInt32(result["player_count"]),
                Allied = teams != null && teams.TryGetValue("allied", out object allied) ? Convert.ToInt32(allied) : 0,
                Axis = teams != null && teams.TryGetValue("axis", out object axis) ? Convert.ToInt32(axis) : 0,
            };
        }
    }
}
