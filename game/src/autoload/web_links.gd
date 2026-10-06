class_name WebLinks
## Links of the browser version: the site and the apps. The page
## (game/web/shell.html) holds them in window.AVTODROM; these are the same
## addresses for a page without it.

const SITE := "https://www.avtotestu.uz/"
const WINDOWS := "https://pub-ada2d6b89d42476e891d0e3b45ca4777.r2.dev/AvtoSmart-Avtodrom-Setup-1.0.7.exe"
const ANDROID := "https://pub-ada2d6b89d42476e891d0e3b45ca4777.r2.dev/AvtoSmart-Avtodrom-1.0.7.apk"


static func _page(key: String, fallback: String) -> String:
	if not OS.has_feature("web"):
		return fallback
	var v: Variant = JavaScriptBridge.eval("(window.AVTODROM && window.AVTODROM.%s) || ''" % key, true)
	return str(v) if v is String and v != "" else fallback


## The app for this device ("" where there is none: iPhone, Linux, Mac).
static func app_url() -> String:
	if OS.has_feature("web_android"):
		return _page("android", ANDROID)
	if OS.has_feature("web_windows"):
		return _page("windows", WINDOWS)
	return ""


## Back to the site in this tab.
static func open_site() -> void:
	var url := _page("site", SITE)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = %s" % JSON.stringify(url), true)
	else:
		OS.shell_open(url)
