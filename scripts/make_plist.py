#!/usr/bin/env python3
"""Regenerate workflow/info.plist (dev-only, stdlib only).

Object graph:
  ip / mac Script Filters ──↩──▶ Conditional {var:action} == "update"
                                    ├─ yes ─▶ Run Script action.sh ─▶ Notification
                                    └─ else ─▶ Copy to Clipboard (paste)
                          ──⌘↩─▶ Copy to Clipboard (copy only)
"""
import plistlib
from pathlib import Path

VERSION = "1.0.0"
CMD = 1048576
U = lambda n: f"6E7F1A00-{n:04d}-4000-8000-{n:012d}"
SF_IP, SF_MAC, PASTE, COPY, COND, ACTION, NOTE = (U(i) for i in range(1, 8))

README = """Network Info — your local and external IP and MAC addresses.

  ip     local IP per interface + external IP (fetched over HTTPS)
  mac    MAC address per hardware port

↩ pastes into the front app · ⌘↩ copies to the clipboard.

The external IP comes from https://api.ipify.org by default (configurable,
https only). Nothing else leaves your Mac.

Source & docs: https://github.com/nadavshatz/alfred-netinfo"""


def script_filter(uid, keyword, arg, title, subtext):
    return {"type": "alfred.workflow.input.scriptfilter", "uid": uid, "version": 3, "config": {
        "alfredfiltersresults": False, "alfredfiltersresultsmatchmode": 0,
        "argumenttreatemptyqueryasnil": True, "argumenttrimmode": 0, "argumenttype": 2,
        "escaping": 102, "keyword": keyword, "queuedelaycustom": 3,
        "queuedelayimmediatelyinitially": True, "queuedelaymode": 0, "queuemode": 1,
        "runningsubtext": "Examining network…", "script": "",
        "scriptargtype": 1, "scriptfile": f"{arg}.sh", "subtext": subtext, "title": title,
        "type": 8, "withspace": False}}


def clipboard(uid, paste):
    return {"type": "alfred.workflow.output.clipboard", "uid": uid, "version": 3, "config": {
        "autopaste": paste, "clipboardtext": "{query}",
        "ignoredynamicplaceholders": False, "transient": False}}


def link(dst, mods=0, sub=""):
    return {"destinationuid": dst, "modifiers": mods, "modifiersubtext": sub, "vitoclose": False}


def conditional_link(dst, output):
    d = link(dst)
    d["sourceoutputuid"] = output
    return d


COND_YES = "6E7F1A00-0099-4000-8000-000000000099"

objects = [
    script_filter(SF_IP, "{var:ip_keyword}", "ip", "Network Info: IP addresses",
                  "Local IP per interface and your external IP"),
    script_filter(SF_MAC, "{var:mac_keyword}", "mac", "Network Info: MAC addresses",
                  "MAC address per hardware port"),
    clipboard(PASTE, True),
    clipboard(COPY, False),
    {"type": "alfred.workflow.utility.conditional", "uid": COND, "version": 1, "config": {
        "conditions": [{"inputstring": "{var:action}", "matchcasesensitive": True,
                        "matchmode": 0, "matchstring": "update", "outputlabel": "update",
                        "uid": COND_YES}],
        "elselabel": "copy", "hideelse": False}},
    {"type": "alfred.workflow.action.script", "uid": ACTION, "version": 2, "config": {
        "concurrently": False, "escaping": 102, "script": "", "scriptargtype": 1,
        "scriptfile": "action.sh", "type": 8}},
    {"type": "alfred.workflow.output.notification", "uid": NOTE, "version": 1, "config": {
        "lastpathcomponent": False, "onlyshowifquerypopulated": True,
        "removeextension": False, "text": "{query}", "title": "Network Info"}},
]

connections = {
    SF_IP: [link(COND), link(COPY, CMD, "Copy to clipboard")],
    SF_MAC: [link(COND), link(COPY, CMD, "Copy to clipboard")],
    COND: [conditional_link(ACTION, COND_YES), link(PASTE)],
    ACTION: [link(NOTE)],
}


def textfield(var, label, default, desc):
    return {"type": "textfield", "variable": var, "label": label, "description": desc,
            "config": {"default": default, "placeholder": default, "required": True, "trim": True}}


user_config = [
    textfield("ip_keyword", "IP keyword", "ip", ""),
    textfield("mac_keyword", "MAC keyword", "mac", ""),
    textfield("ext_ip_url", "External IP service", "https://api.ipify.org",
              "Must start with https://. The response must be a bare IPv4 or IPv6 address."),
    {"type": "popupbutton", "variable": "update_mode", "label": "Updates",
     "description": "Checks GitHub Releases once a day. Installing always goes through Alfred's own update prompt.",
     "config": {"default": "notify", "pairs": [["Tell me in Alfred", "notify"],
                                              ["Download and open automatically", "auto"],
                                              ["Never check", "off"]]}},
]

pos = {SF_IP: (40, 60), SF_MAC: (40, 220), COND: (260, 140), ACTION: (460, 40),
       NOTE: (660, 40), PASTE: (460, 200), COPY: (460, 330)}

plist = {
    "bundleid": "io.github.nadavshatz.netinfo",
    "category": "Tools",
    "connections": connections,
    "createdby": "Nadav Shatz",
    "description": "Local and external IP and MAC addresses",
    "disabled": False,
    "name": "Network Info",
    "objects": objects,
    "readme": README,
    "uidata": {u: {"xpos": x, "ypos": y} for u, (x, y) in pos.items()},
    "userconfigurationconfig": user_config,
    "version": VERSION,
    "webaddress": "https://github.com/nadavshatz/alfred-netinfo",
}

out = Path(__file__).resolve().parent.parent / "workflow" / "info.plist"
out.write_bytes(plistlib.dumps(plist, sort_keys=True))
print(f"wrote {out}")
