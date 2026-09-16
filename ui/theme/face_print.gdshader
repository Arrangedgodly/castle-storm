// FacePrint — the two-ink face print pass (T-UI-01 round-2 fix).
//
// The vendored Kenney pose sheets are FULL COLOR sprites; dropped raw on a
// paper card they read as a colored (round-1: near-black) plate, not the
// cheap two-ink print the design brief commits to ("faces are flat vector
// portraits, asset-pack + recolor/compose at MVP" — the recolor half).
// This shader is that composition step, applied by FaceSlot to landed face
// art ONLY (the authored placeholder never passes through it):
//   - source LUMINANCE maps to ink coverage: dark lines print solid ink,
//     light areas fall back to a thin wash (the figure keeps its volume),
//     so the portrait reads as one printing-ink pass on paper;
//   - the source ALPHA is preserved — the sheets' ground is fully
//     transparent (pixel-probe verified), so the paper stock shows through
//     everywhere the press did not ink: no plate behind the face;
//   - the ink COLOR is a uniform (Inks.INK from FaceArt), keeping the
//     palette single-sourced and regime-independent — faces are content,
//     the frame carries the regime accent.
shader_type canvas_item;

uniform vec4 ink_color : source_color = vec4(0.118, 0.098, 0.078, 1.0);
// Thin-ink floor for the lightest source pixels (0 = pure line art).
uniform float wash_floor : hint_range(0.0, 0.5) = 0.14;
// Luma band edges: at/below `shadow_luma` prints solid, at/above
// `paper_luma` prints only the wash floor.
uniform float shadow_luma = 0.16;
uniform float paper_luma = 0.78;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float luma = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
	float coverage = 1.0 - smoothstep(shadow_luma, paper_luma, luma);
	float a = tex.a * mix(wash_floor, 1.0, coverage);
	COLOR = vec4(ink_color.rgb, a);
}
