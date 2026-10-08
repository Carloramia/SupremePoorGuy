extends SceneTree

func _initialize() -> void:
	var shapes: Dictionary = {
		"Hero": '<path d="M72 208 L58 282 L92 286 L108 220 L120 286 L153 280 L137 204 Z" fill="#374c63"/><path d="M55 96 Q108 75 158 98 L144 214 Q102 235 64 210 Z" fill="#729c98"/><path d="M61 107 L26 179 L47 196 L80 132 M147 105 L183 169 L162 185 L131 130" fill="#ead6b5"/><ellipse cx="106" cy="62" rx="35" ry="43" fill="#ead6b5"/><path d="M70 48 Q75 4 115 20 Q148 17 144 59 L129 46 L112 38 L84 57 Z" fill="#514237"/><path d="M80 156 L145 158 M91 64 L96 66 M119 65 L124 63" fill="none"/>',
		"NPC": '<path d="M73 206 L62 279 L94 287 L109 223 L123 285 L153 278 L139 202 Z" fill="#594858"/><path d="M55 109 Q106 76 158 110 L153 220 L63 220 Z" fill="#c09162"/><ellipse cx="106" cy="69" rx="32" ry="39" fill="#e7cbb0"/><path d="M65 61 L77 27 L127 23 L151 59 Z" fill="#ab604e"/><path d="M92 72 L97 73 M119 72 L125 70 M81 155 L132 167" fill="none"/><path d="M158 107 L183 180 L165 190 L141 134" fill="#e7cbb0"/>',
		"Tree": '<path d="M89 169 L82 284 L126 283 L117 168 Z" fill="#947456"/><path d="M100 18 Q58 27 59 62 Q14 72 36 110 Q7 148 55 176 Q67 210 111 188 Q159 211 182 163 Q218 138 177 106 Q191 62 153 54 Q144 12 100 18 Z" fill="#729675"/><path d="M50 110 Q89 135 135 96 M82 166 L108 140 L139 162 M96 251 L108 200" fill="none" stroke="#48684e"/>',
		"Crate": '<path d="M24 100 L105 68 L184 102 L181 249 L104 285 L25 250 Z" fill="#b99464"/><path d="M24 100 L104 137 L184 102 M104 137 L104 285 M31 139 L94 166 M32 208 L94 236 M116 166 L174 138 M116 237 L174 209" fill="none"/><path d="M38 119 L91 261 M37 243 L89 149 M119 149 L170 243 M119 263 L171 120" fill="none" stroke="#e6c68b" stroke-width="12"/>'
	}
	for name in shapes:
		var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="212" height="304" viewBox="0 0 212 304"><g stroke="#423e35" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">' + shapes[name] + '</g></svg>'
		var image := Image.new()
		image.load_svg_from_string(svg, 2.0)
		image.fix_alpha_edges()
		image.save_png("res://scenario_2_5d/demo/assets/" + name + ".png")
	quit()
