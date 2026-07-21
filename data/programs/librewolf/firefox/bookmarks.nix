
/*
  NOTE: syntax
    see https://home-manager-options.extranix.com/?query=firefox+bookmarks

  NOTE: organizing
    I'm just splattering a bunch of bookmarks without organization / folders /tags.
    Keeps it simple for autocompleting from bookmarks/history
*/
let
  # helper function to construct attrset pairing { name=$name; url=$url; }
  f = name: url: { inherit name url; };
  prefix = {
    about = "#";
    LAN   = "@";
  };
in
[
  # the backrooms (or rather, a few shortcuts to them)
    (f "${prefix.about}about"         "about:about")
    (f "${prefix.about}add"           "about:addons")
    (f "${prefix.about}conf"          "about:config")
    (f "${prefix.about}mem"           "about:memory")
    (f "${prefix.about}proc"          "about:processes")
    (f "${prefix.about}cache"         "about:cache")
    (f "${prefix.about}url"           "about:url-classifier")
    (f "${prefix.about}tab"           "about:unloads")
    (f "${prefix.about}tel"           "about:telemetry") # should be blocked...
    (f "${prefix.about}net"           "about:networking")
    (f "${prefix.about}log"           "about:logging")
    (f "${prefix.about}def"           "about:protections")
    (f "${prefix.about}this"          "about:debugging#/runtime/this-firefox")
    (f "${prefix.about}policy"        "about:policies#active")
    (f "${prefix.about}trouble"       "about:support")

  # search engines (these are just bookmarks; see searchengines.nix for search shortcuts)
    (f "Kagi"                         "https://kagi.com")
    (f "DuckDuckGo"                   "https://duckduckgo.com")
    (f "Brave Search"                 "https://search.brave.com")
    (f "Mojeek"                       "https://www.mojeek.com")
    (f "Searxng"                      "https://searxng.site")
    (f "Bing"                         "https://bing.com")
    (f "Google"                       "https://google.com")
    (f "Yahoo"                        "https://www.yahoo.com")
    (f "Qwant"                        "https://www.qwant.com")
    (f "Dogpile"                      "https://www.dogpile.com")

  # misc
    (f "Google Translate"             "https://translate.google.ca/?sl=en&tl=ja&op=translate")
    (f "Wikipedia"                    "https://en.wikipedia.org")
    (f "Mycroft Project"              "https://mycroftproject.com")
    (f "EFF"                          "https://www.eff.org")

  # programming related
    # repo
    (f "Github"                       "https://github.com")
    (f "Gitlab"                       "https://gitlab.com")
    (f "Hugging Face"                 "https://huggingface.co")
    # nix stuff
    (f "NixOS"                        "https://nixos.org")
    (f "NixOS Wiki"                   "https://wiki.nixos.org")
    (f "NixHub"                       "https://www.nixhub.io/")
    (f "MyNixOS"                      "https://mynixos.com")
    (f "Nix Status"                   "https://status.nixos.org/")
    (f "Home Manager"                 "https://github.com/nix-community/home-manager")
    (f "Home Manager Options"         "https://nix-community.github.io/home-manager/options.xhtml")
    # microsoft
    (f "Microsoft Windows"            "https://learn.microsoft.com/en-us/windows/")
    # C/C++ stuff
    (f "winlibs"                      "https://winlibs.com")
    (f "Godbolt Compiler Explorer"    "https://godbolt.org")
    (f "creference"                   "https://en.cppreference.com/w/c")
    (f "cppreference"                 "https://en.cppreference.com/w")
    # Python stuff
    (f "Python 3"                     "https://docs.python.org/3")
    (f "Python 3 QT"                  "https://doc.qt.io/qtforpython-6.6/api.html")

  # financial
    # gov
    (f "CRA"                          "https://www.canada.ca/en/revenue-agency/services/e-services/cra-login-services.html")
    (f "HST"                          "https://www.canada.ca/en/revenue-agency/services/e-services/digital-services-businesses/gst-hst-netfile.html")
    (f "IRS"                          "https://www.irs.gov/your-account")
    (f "TAP"                          "https://tap.dor.mt.gov")
    # banks
    (f "TD"                           "https://www.td.com/ca/en/personal-banking")
    (f "BMO"                          "https://www1.bmo.com/banking/digital/login?lang=en")
    (f "RBC"                          "https://secure.royalbank.com/statics/login-service-ui/index#/full/signin?LANGUAGE=ENGLISH")
    (f "Libro"                        "https://my.libro.ca/Login")
    # utilities
    (f "Bell Canada"                  "https://mybell.bell.ca/Login")
    (f "Rogers"                       "https://www.rogers.com")
    (f "Enbridge Gas"                 "https://www.enbridgegas.com")
    # accounting
    (f "Intuit"                       "https://www.intuit.com/ca")
    (f "Quickbooks - Intuit"          "https://qbo.intuit.com/app/homepage?locale=en-CA")
    (f "Freshbooks"                   "https://auth.freshbooks.com/service/auth/integrations/sign_in")
    (f "Zipbooks"                     "https://app.zipbooks.com/login")
    # ecommerce
    (f "PayPal"                       "https://www.paypal.com")
    (f "Wise"                         "https://wise.com")
    (f "Macro Foods"                  "https://macrofoods.ca")
    (f "LiveFitFood"                  "https://livefitfood.ca")
    (f "Zehrs"                        "https://www.zehrs.ca")
    (f "Canadian Tire"                "https://www.canadiantire.ca")
    (f "Domino's Pizza"               "https://www.dominos.ca")
    (f "New Olreans Pizza"            "https://www.neworleanspizza.com")
    (f "Subway"                       "https://www.subway.com/en-ca")
    (f "West Sushi"                   "https://westsushi.ca")
    (f "LTTStore"                     "https://www.lttstore.com")
    (f "Facebook Marketplace"         "https://www.facebook.com/marketplace")
    (f "eBay (CA)"                    "https://www.ebay.ca")
    (f "eBay (US)"                    "https://www.ebay.com")
    (f "Amazon (CA)"                  "https://www.amazon.ca")
    (f "Amazon (US)"                  "https://www.amazon.com")
    (f "NewEgg (CA)"                  "https://www.newegg.ca")
    (f "NewEgg (US)"                  "https://www.newegg.com")
    (f "Memory Express"               "https://www.memoryexpress.com")
    (f "Canada Computers"             "https://www.canadacomputers.com")
    (f "Microcenter"                  "https://www.microcenter.com")
    (f "PCPartPicker"                 "https://pcpartpicker.com") # maybe should be a utility...

  # suites
    (f "Proton"                       "https://proton.me")
    (f "Mail"                         "https://mail.com")
    (f "Eastlink Webmail"             "https://my.eastlink.ca/webmail")
    (f "Eastlink Account"             "https://my.eastlink.ca/myaccount")

  # utility
    (f "ChatGPT"                      "https://chat.openai.com")
    (f "T3 Chat"                      "https://t3.chat")
    (f "JustBeamIt"                   "https://justbeamit.com")
    (f "OpenTogetherTube"             "https://opentogethertube.com")
    (f "Pastebin"                     "https://pastebin.com")
    (f "VirusTotal"                   "https://www.virustotal.com/gui")
    (f "Merge images online"          "https://merge.imageonline.co")
    (f "Regex101"                     "https://regex101.com")
    (f "Excalidraw"                   "https://excalidraw.com")
    (f "JSON Formatter"               "https://jsonformatter.org")
    (f "loader.to"                    "https://en.loader.to")

    # domains & dns
    (f "Namecheap"                    "https://www.namecheap.com")
    (f "Dynadot"                      "https://www.dynadot.com")
    (f "Porkbun"                      "https://porkbun.com")
    (f "Cloudflare"                   "https://www.cloudflare.com")
    (f "EasyDNS"                      "https://easydns.com")
    (f "FreeDNS - Afraid.org"         "https://freedns.afraid.org")

  # applications
    (f "HexOS"                        "https://hexos.com")
    (f "TrueNAS"                      "https://www.truenas.com")
    (f "mpv"                          "https://mpv.io")
    (f "mpv (git)"                    "https://github.com/mpv-player/mpv")
    (f "Freetube"                     "https://github.com/FreeTubeApp/FreeTube")
    (f "GCC docs"                     "https://gcc.gnu.org/onlinedocs/gcc/Invoking-GCC.html")
    (f "Syncplay"                     "https://syncplay.pl")
    (f "Xonsh"                        "https://xon.sh")

  # entertainment
    # edu
    (f "Waterloo"                     "https://uwaterloo.ca/engineering-faculty-staff-resources/user/login")
    (f "MIT-RAS"                      "https://ras.mit.edu/mit-login")
    (f "Khan Academy"                 "https://www.khanacademy.org/login")
    # downloads
    (f "Fitgirl Repacks"              "https://fitgirl-repacks.site")
    (f "Nexus Mods"                   "https://www.nexusmods.com")
    (f "Nyaa.si"                      "https://nyaa.si")
    (f "Anime Tosho"                  "https://animetosho.org")
    (f "Torrent Galaxy"               "https://torrentgalaxy.to")
    (f "bthub"                        "https://bthub.cc/en")
    (f "Civitai Models"               "https://civitai.com/models?tag=base+model")
    # gaming
    (f "ProtonDB"                     "https://www.protondb.com")
    (f "Steam"                        "https://store.steampowered.com")
    (f "Itch.io"                      "https://itch.io")
    (f "Good Old Games"               "https://www.gog.com")
    (f "Epic Games"                   "https://store.epicgames.com/en-US")
    (f "Humble Bundle"                "https://www.humblebundle.com")
    (f "Warframe"                     "https://forums.warframe.com")
    (f "BDO - Black Desert Online"    "https://www.naeu.playblackdesert.com/en-US")
    (f "BDO - Garmoth"                "https://garmoth.com")
    # streaming
    (f "YouTube"                      "https://www.youtube.com")
    (f "Floatplane"                   "https://www.floatplane.com/login")
    (f "Netflix"                      "https://www.netflix.com")
    (f "Jellyfin - Futa.zip"          "https://jellyfin.futa.zip")
    # socials
    (f "MyAnimeList (MAL)"            "https://myanimelist.net")
    (f "Reddit"                       "https://www.reddit.com")
    (f "Imgur"                        "https://imgur.com")
    (f "Bluesky (bsky)"               "https://bsky.app")
    (f "Discord"                      "https://discord.com")
    (f "L1 - Level 1 Techs Forums"    "https://forum.level1techs.com")
    (f "LTT - LinusTechTips Forums"   "https://linustechtips.com")

]
