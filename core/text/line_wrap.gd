extends RefCounted
## 中文的換行。
##
## 中文沒有空白可以斷行，交給引擎自動換行的話，常會剩下一兩個字自成一行，
## 或是讓句號、下引號落在行首。這裡把一段文字排成長短相近的幾行，
## 盡量在標點後面換行，而且不讓標點落在行首。

## 可以在後面換行、但不能出現在行首的標點。
const BREAK_AFTER := "，。、；：！？」）"

## 找標點時，依序試目標位置的前後這幾個字。
const OFFSETS := [0, 1, -1, 2, -2, 3, -3, 4, -4]


## 把 text 排成每行不超過 max_chars 個字。原本就有的換行會保留。
static func balanced(text: String, max_chars: int) -> String:
	max_chars = maxi(2, max_chars)
	var lines: PackedStringArray = []
	for paragraph in text.split("\n"):
		var rest := paragraph
		while rest.length() > max_chars:
			var count := ceili(float(rest.length()) / max_chars)
			var target := ceili(float(rest.length()) / count)
			var cut := _find_break(rest, target, max_chars)
			lines.append(rest.substr(0, cut))
			rest = rest.substr(cut)
		lines.append(rest)
	return "\n".join(lines)


## 回傳這一行要放幾個字。先在目標位置附近找標點；找不到就照目標位置切，只避開行首的標點。
static func _find_break(text: String, target: int, max_chars: int) -> int:
	for offset: int in OFFSETS:
		var at := target + offset
		if at < 2 or at > max_chars or at >= text.length():
			continue
		if BREAK_AFTER.contains(text[at - 1]) and not BREAK_AFTER.contains(text[at]):
			return at
	var cut := mini(target, max_chars)
	while cut < text.length() - 1 and cut < max_chars and BREAK_AFTER.contains(text[cut]):
		cut += 1
	while cut > 2 and BREAK_AFTER.contains(text[cut]):
		cut -= 1
	return cut
