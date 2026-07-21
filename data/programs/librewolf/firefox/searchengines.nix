
/*
  NOTE: bangs
    All my search engines have browser-local !bang shortcuts.
    This is preferred over an engine's bang (like DDG bangs) because
    that indirect is slower and may leak query.

    See `alias` / `definedAliases` for the definition.

  NOTE: finding / updating search engines
    If you're struggling to figure out a search engine, https://mycroftproject.com
    offers OpenSearch plugins for adding search engines to various browsers. Once
    a plugin is installed, you can see what it added by following the HOWTO.

  NOTE:HOWTO: import from firefox
    Engines were manually translated from my existing browser data.
    Firefox search engine definitions are kept in `search.json.mozlz4`

    0.  Get archive tool capable of decompressing `mozlz4a`.
        e.g. https://gist.github.com/Tblue/62ff47bef7f894e92ed5
        e.g. https://search.nixos.org/packages#?query=mozlz4a

    1.  Find the `search.json.mozlz4` file in your firefox profile and decompress it.
        e.g. copy it to a new folder run `mozlz4a -d search.json.mozlz4 search.json`

    2.  Translate to nix.
        You may want to strip out all of the `data/image` noise
        and replace `{"id":` -> `\n\n{"id":` to improve readibility.

    For nix syntax, see (A) which corresponds to json parameters for (B) -- B should be linked in A.
      A) https://nix-community.github.io/home-manager/options.xhtml#opt-programs.firefox.profiles._name_.search.engines
      B) https://searchfox.org/mozilla-central/rev/669329e284f8e8e2bb28090617192ca9b4ef3380/toolkit/components/search/SearchEngine.jsm#1138-1177
*/

{
  force = true;
  default = "k";
  privateDefault = "ddg";

  # omitting suggestion urls since I don't use them...
  engines =
  let
    prefix.search = "!";

    # for adding new custom engines
    n = alias: name: urls: {
      name = alias;
      value = {
        name = name;
        urls = urls;
        definedAliases = [ "${prefix.search}${alias}" ];
        metaData.hideOneOffButton = true;
      };
    };

    # for aliasing vanilla engines
    a = alias:  id: {
      name = id;
      value = {
        metaData = {
          alias = "${prefix.search}${alias}";
          hideOneOffButton = true;
        };
      };
    };

    # for hiding vanilla engines
    h = id: {
      name = id;
      value = { metaData.hideOneOffButton = true; };
    };

  in builtins.listToAttrs [
# hide fluff
  (h "policy-StartPage")
  (h "policy-Mojeek")
  (h "policy-MetaGer")
  (h "policy-DuckDuckGo Lite")
  (h "policy-SearXNG - searx.be")
# General
  (n "k"     "Kagi"                 [{ template = "https://kagi.com/search?q={searchTerms}"; }])
  (n "ki"    "Kagi Images"          [{ template = "https://kagi.com/images?q={searchTerms}"; }])
  (a "d"     "ddg")
  (n "di"    "DuckDuckGo Images"    [{ template = "https://duckduckgo.com/?kp=-2&q={searchTerms}&iax=images&ia=images"; }])
  (a "b"     "bing")
  (n "bi"    "Bing Images"          [{ template = "http://www.bing.com/images/search?q={searchTerms}&adlt=off"; }])
  (n "m"     "Mojeek"               [{ template = "https://www.mojeek.com/search?q={searchTerms}&theme=dark&arc=none&t=20&tn=10&newtab=1&si=2&lb=en&qss=Bing%2CBrave%2CGoogle%2CQwant%2CStartpage%2CYandex"; }])
  (n "q"     "Quant"                [{ template = "https://www.qwant.com?q={searchTerms}&client=opensearch"; }])
  (n "s"     "SearXNG"              [{ template = "https://searxng.site/searxng/search"; params = [ { name = "q"; value = "{searchTerms}"; } ]; }])
  (a "g"     "google") # google images is pretty useless so I'm omitting it
# Programming
  # nix stuff
  (n "np"    "Nix Packages"         [{ template = "https://search.nixos.org/packages"; params = [ { name = "type"; value = "packages"; } { name = "query"; value = "{searchTerms}"; } ];}])
  (n "npv"   "Nix Package Versions" [{ template = "https://lazamar.co.uk/nix-versions/?channel=nixos-unstable&package={searchTerms}"; }])
  (n "no"    "Nix Options"          [{ template = "https://search.nixos.org/options?query={searchTerms}"; }])
  (n "nh"    "Nix Hub"              [{ template = "https://www.nixhub.io/search?q=searchTerms}"; }])
  (n "nw"    "NixOS Wiki"           [{ template = "https://wiki.nixos.org/w/index.php?search={searchTerms}"; }])
  # windows
  (n "msd"   "Microsoft Learn Docs" [{ template = "https://learn.microsoft.com/en-us/search/?terms={searchTerms}"; }])
  # python
  (n "py"    "Python 3"             [{ template = "https://docs.python.org/3/search.html?q={searchTerms}"; }])
  (n "pyqt"  "Python Qt"            [{ template = "https://doc.qt.io/qtforpython-6.6/search.html?check_keywords=yes&area=default&q={searchTerms}"; }])
  # C++
  (n "cpp"   "C++ Reference"        [{ template = "https://en.cppreference.com/mwiki/index.php?title=Special:Search&fulltext=1&search={searchTerms}"; }])
# Content
  (a "w"     "wikipedia")
  (n "yt"    "Youtube"              [{ template = "https://www.youtube.com/results?search_query={searchTerms}"; }])
  (n "mal"   "My Anime List"        [{ template = "http://myanimelist.net/anime.php?q={searchTerms}"; }])
  (n "nya"   "Nyaa.si"              [{ template = "https://nyaa.si/?q={searchTerms}&f=0&c=0_0&s=seeders&o=desc"; }])
  (n "to"    "Anime Tosho"          [{ template = "https://animetosho.org/search?q={searchTerms}"; }])
  (n "bh"    "bthub"                [{ template = "https://bthub.cc/en/search/kw-{searchTerms}-1.html"; }])
# Applications, gaming, stores
  (n "am"    "Amazon (CA)"          [{ template = "https://www.amazon.ca/s?k={searchTerms}"; }])
  (n "amus"  "Amazon (US)"          [{ template = "https://www.amazon.com/s?k={searchTerms}"; }])
  (n "bdo"   "BDO Codex"            [{ template = "https://bdocodex.com/us/search/{searchTerms}"; }])
  (n "pdb"   "ProtonDB"             [{ template = "https://www.protondb.com/search?q={searchTerms}"; }])
  (n "steam" "Steam"                [{ template = "https://store.steampowered.com/search/?term={searchTerms}"; }])
  (n "itch"  "Itch.io"              [{ template = "https://itch.io/search?q={searchTerms}"; }])
  (n "gog"   "Good Old Games"       [{ template = "https://www.gog.com/en/games?query={searchTerms}"; }])
  (n "epic"  "Epic"                 [{ template = "https://store.epicgames.com/en-US/browse?q=test{searchTerms}"; }])
# Utility
  (n "dict"  "Dictionary"           [{ template = "https://www.dictionary.com/browse/{searchTerms}"; }])
  (n "thes"  "Thesaurus"            [{ template = "https://www.thesaurus.com/browse/{searchTerms}"; }])
  ];
}
