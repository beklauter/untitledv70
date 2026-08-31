// Props, double sided. For tent canvas, cloth and other thin geometry.
// Same body as pa_props. Draws both faces and flips backface normals.
shader_type spatial;
render_mode cull_disabled;
#define PROPS_TWO_SIDED
#include "res://Polyart/SharedResources/Shaders/pa_props_body.gdshaderinc"
