package ui

import "core:log"
import "core:math/linalg"

import "core:fmt"
import "../render"
import "../util"

label :: proc(
	ctx: ^UI_Context,
	str: string,
	alignment: Alignment = {.Left, .Middle},
	theme: ^Text_Theme = nil,
	ui_id: UI_ID = 0,
	location := #caller_location,
) -> (state: Element_State)
{
	ui_id := ui_id;
	if ui_id == 0 do ui_id = id_from_location(location);
	layout_rect := current_layout_rect(ctx);

	font := theme != nil ? theme.font_asset : ctx.current_theme.text.default.font_asset;

	font_data := ctx.font_loader.loaded_fonts[font];
	line_height := font_data.line_height;
	lines := render.split_text_for_render(font_data, str, int(layout_rect.size.x));
	allocated_length := layout_rect.size.x;
	if len(lines) == 1
	{
		allocated_length = render.get_text_render_size(font_data, str);
	}
	allocated_space := allocate_element_space(ctx, [2]int{allocated_length, int(f32(len(lines)) * line_height)});

	first_line_pos := allocated_space.pos;

	alignment_ratios: [2]f32;
	switch alignment.horizontal
	{
		case .Left: alignment_ratios.x = 0;
		case .Center: alignment_ratios.x = 0.5;
		case .Right: alignment_ratios.x = 1;
	}
	switch alignment.vertical
	{
		case .Top: alignment_ratios.y = 0;
		case .Middle: alignment_ratios.y = 0.5;
		case .Bottom: alignment_ratios.y = 1;
	}
	for line, index in lines
	{
		text(
			text = line,
			pos = first_line_pos + UI_Vec{int(f32(allocated_space.size.x) * alignment_ratios.x), int(f32(allocated_space.size.y) * (f32(index) + alignment_ratios.y))},
			alignment = alignment,
			theme = theme,
			ctx = ctx,
		);
	}
	
	return state;
}

drag_int :: proc(ctx: ^UI_Context, value: ^int, ui_id: UI_ID = 0, location := #caller_location)
{
	ui_id := default_id(ui_id, location);
	parent_layout := current_layout(ctx)^;
	widget_rect := allocate_element_space(ctx, {0, int(ctx.editor_config.line_height)});
	state := ui_element(ctx, widget_rect, {.Hover, .Press, .Drag}, ui_id ~ id_from_location());
	text_color := render.rgb(255, 255, 255);
	if Interaction_Type.Drag in state
	{
		value^ += int(ctx.input_state.delta_drag.x);
	}
	if Interaction_Type.Drag in state || Interaction_Type.Press in state
	{
		text_color &= 0x00ffffff;
		element_draw_rect(ctx, default_anchor, {}, render.rgb(200, 200, 0), 5);
	}
	else if Interaction_Type.Hover in state 
	{
		text_color &= 0x00ffffff;;
		element_draw_rect(ctx, default_anchor, {}, render.rgb(255, 255, 0), 5);
	}
	new_layout := Layout {
		rect = widget_rect,
		direction = {1, 0},
	};
	push_layout(ctx, new_layout);
	text_theme := ctx.current_theme.text.default;
	text_theme.color = text_color;
	label(ctx, "drag editor ", {.Left, .Middle}, &text_theme, ui_id ~ id_from_location());
	label(ctx, fmt.tprint(value^), {.Left, .Middle}, &text_theme, ui_id ~ id_from_location());
	pop_layout(ctx);
}

slider :: proc(
	ctx: ^UI_Context,
	value: ^$T,
	min, max: T,
	cursor_size: int,
	thickness: int,
	ui_id: UI_ID = 0,
	location := #caller_location,
) -> (value_changed: bool)
{
	ui_id := default_id(ui_id);
	direction_vec: [2]int;
	tangent_vec: [2]int;
	parent_layout := current_layout(ctx)^;

	if parent_layout.direction.y != 0
	{
		// Vertical layout => horizontal slider
		direction_vec.x = 1;
		tangent_vec.y = 1;
	}
	else
	{
		// Horizontal layout => horizontal slider
		direction_vec.y = 1;
		tangent_vec.x = 1;
	}

	widget_rect := allocate_element_space(ctx, tangent_vec * thickness);
	theme := ctx.current_theme.slider;
	add_rect_command(&ctx.ui_draw_list, Rect_Command{
		rect = widget_rect,
		theme = theme.background_theme,
	});
	value_ratio := f32(value^ - min) / f32(max - min);

	max_cursor_pos: int = linalg.vector_dot(widget_rect.size, direction_vec); 
	cursor_rect := UI_Rect {
		pos = widget_rect.pos + direction_vec * (cursor_size / 2 + int(f32(max_cursor_pos - cursor_size) * value_ratio) - cursor_size / 2),
		size = cursor_size * direction_vec + widget_rect.size * tangent_vec,
	};
	cursor_state := ui_element(ctx, cursor_rect, {.Hover, .Press, .Drag}, child_id(ui_id));
	cursor_theme : Rect_Theme = theme.foreground_theme.default_theme;
	if Interaction_Type.Press in cursor_state
	{
		ctx.active_widget_data = value^;
	}
	if Interaction_Type.Drag in cursor_state
	{
		drag_offset := f32(linalg.vector_dot(ctx.input_state.drag_amount, direction_vec)) / f32(max_cursor_pos - cursor_size) * f32(max - min);
		drag_start_value, cast_ok := ctx.active_widget_data.(T);
		if cast_ok
		{
			new_value : T = drag_start_value + T(drag_offset);
			if new_value < min do new_value = min;
			if new_value > max do new_value = max;
			if new_value != value^
			{
				value^ = new_value;
				value_changed = true;
			}
		}
		else
		{
			log.info("Error : slider dragged while not the active widget")
		}
		cursor_theme = theme.foreground_theme.clicked_theme;
	}
	else if Interaction_Type.Hover in cursor_state
	{
		cursor_theme = theme.foreground_theme.hovered_theme;
	}
	add_rect_command(&ctx.ui_draw_list, Rect_Command{
		rect = cursor_rect,
		theme = cursor_theme,
	});
	return;
}

window :: proc(using ctx: ^UI_Context, using state: ^Window_State, header_height: int, ui_id : UI_ID = 0, location := #caller_location) -> (draw_content: bool)
{ 
	ui_id := default_id(ui_id);

	header_size := UI_Vec{rect.size.x, header_height};
	header_layout := Layout {
		rect = UI_Rect{
			pos = rect.pos,
			size = header_size,
		},
		direction = {-1, 0},
	};
	theme := current_theme.window;

	push_layout(ctx, header_layout);
	layout_draw_rect(ctx, {}, {}, {fill_color = theme.header_color});
	if button(ctx, "close button", UI_Vec{header_height, header_height}, nil, child_id(ui_id))
	{

	}
	pop_layout(ctx);
	header_layout.direction.x = 1;
	push_layout(ctx, header_layout);
	if button(ctx, "fold button", UI_Vec{header_height, header_height}, nil, child_id(ui_id))
	{
		state.folded = !state.folded;
	}
	draw_content = !state.folded;

	header_outline_rect := current_layout(ctx).rect;
	header_outline_rect.pos -= {1, 1};
	header_outline_rect.size += {2, 2};
	drag_offset: [2]int;
	if drag_box(UI_Rect{rect.pos, header_size}, &drag_state, ctx, child_id(ui_id))
	{
		drag_offset = drag_state.drag_offset;
		drag_state.drag_offset = {0, 0};
	}
	// Close button
	pop_layout(ctx);
	if draw_content
	{
		// Body Layout
		scrollbar_width := 20;
		body_layout := Layout {
			rect = UI_Rect {
				pos = rect.pos + UI_Vec{0, header_height},
				size = UI_Vec{rect.size.x - scrollbar_width, rect.size.y - header_height},
			},
			direction = {0, 1},
		};
		push_layout(ctx, body_layout);

		if last_frame_height != 0
		{
			view_height:= rect.size.y - header_height;
			scrollbar_layout := Layout {
				rect = UI_Rect {
					pos = rect.pos + UI_Vec{body_layout.rect.size.x, header_height},
					size = UI_Vec{scrollbar_width, view_height},
				},
				direction = {1, 0},
			};
			push_layout(ctx, scrollbar_layout);
			scroll_max := last_frame_height - view_height;
			cursor_size := view_height * view_height / last_frame_height;
			slider(ctx, &scroll, 0, scroll_max, cursor_size, 0, child_id(ui_id));
			pop_layout(ctx);
		}
	}

	//next_layout(ctx);
	if draw_content
	{
		push_clip(&ctx.ui_draw_list, layout_get_rect(ctx, {}, {}));
		layout_draw_rect(ctx, {}, {}, {fill_color = theme.background_color});
		header_outline_rect.size.y += current_layout(ctx).rect.size.y;
		scroll_content_rect := current_layout(ctx).rect;
		//scroll_content_rect.size.y = state.last_frame_height;
		content_layout := Layout{
			rect =	scroll_content_rect,
			direction = {0, 1},
		};
		content_layout.pos += UI_Vec{0, -scroll};
		push_layout(ctx, content_layout);
		add_content_size_fitter(ctx);
	}
	// Handle drag effects at the end to keep a consistent rect.pos through the rendering of the window
	//rect_border(&ctx.draw_list, header_outline_rect, render.rgb(0, 0, 0), 1);
	rect.pos += drag_offset;
	return;
}

window_end :: proc(using ctx: ^UI_Context, using state: ^Window_State)
{
	pop_clip(&ctx.ui_draw_list);
	layout := pop_layout(ctx);
	
	// TODO : handle content height computation
	state.last_frame_height = layout.size.y;
}


color_picker_rgb :: proc(using ctx: ^UI_Context, color: ^Color, height: int = 50, ui_id: UI_ID = 0, location := #caller_location) -> bool
{
	ui_id := default_id(ui_id, location);
	parent_layout := current_layout(ctx);
	color_display_rect := UI_Rect{
		pos = parent_layout.pos,
		size = UI_Vec{height, height},
	};
	push_child_layout(ctx, UI_Vec{0, height}, UI_Vec{1, 0});
	container_rect := allocate_element_space(ctx, UI_Vec{parent_layout.size.x - height, height});

	push_layout(ctx, Layout{
		rect = container_rect,
		direction = UI_Vec{0, 1},
	});
	
	
	// using the extract to int version to fix potential overflow of the value modified with sliders
	r, g, b, a : int = render.extract_rgba_int(color^);
	value_changed := false;
	push_label_layout(ctx, "r", height / 3, 20);
	value_changed |= slider(ctx, &r, 0, 255, 20, 0, child_id(ui_id));
	pop_layout(ctx);
	push_label_layout(ctx, "g", height / 3, 20);
	value_changed |= slider(ctx, &g, 0, 255, 20, 0, child_id(ui_id));
	pop_layout(ctx);
	push_label_layout(ctx, "b", height / 3, 20);
	value_changed |= slider(ctx, &b, 0, 255, 20, 0, child_id(ui_id));
	pop_layout(ctx);
	pop_layout(ctx);
	theme := ctx.current_theme.button;
	theme.default_theme.fill_color = color^
	button_themed(ctx, "", UI_Vec{height, height}, &theme, child_id(ui_id));

	pop_layout(ctx);
	if value_changed do color^ = render.rgba(u8(r), u8(g), u8(b), u8(a));

	return value_changed;
}

number_editor :: proc(
	using ctx: ^UI_Context, 
	value: ^$T,
	increment: T,
	theme: ^Number_Editor_Theme = nil,
	ui_id: UI_ID = 0,
	location := #caller_location,
) -> (result: bool)
{
	ui_id := default_id(ui_id, location);
	push_group(ctx, ctx.current_theme.button.default_theme, Padding{{20, 10}, {50, 10}});
	used_theme := theme;
	if theme == nil do used_theme = &ctx.current_theme.number_editor;
	text_theme := used_theme.text;
	font := ctx.font_loader.loaded_fonts[text_theme.font_asset];
	button_size := UI_Vec{int(used_theme.button_width), int(used_theme.height)};
	layout_rect := current_layout_rect(ctx);
	allocated_rect := allocate_element_space(ctx, UI_Vec{0, used_theme.height});

	
	//push_child_layout(ctx, {0, used_theme.height}, {1, 0});
	if button(ctx, "-", UI_Rect{allocated_rect.pos, button_size}, nil, child_id(ui_id, location, 0), location)
	{
		value^ -= increment;
		result = true;
	}
	text(
		text = fmt.tprint(value^),
		pos = allocated_rect.pos + allocated_rect.size / 2,
		alignment = {.Center, .Middle},
		theme = text_theme,
		ctx = ctx,
	);
	if button(ctx, "+", UI_Rect{allocated_rect.pos + UI_Vec{allocated_rect.size.x - button_size.x, 0}, button_size}, nil, child_id(ui_id, location, 1), location)
	{
		value^ += increment;
		result = true;
	}
	pop_group(ctx);
	return;
}

fold :: proc(
	ctx: ^UI_Context,
	label: string,
	folded: ^bool,
	ui_id: UI_ID = 0,
	location := #caller_location,
) -> (display_content: bool)
{
	// TODO : looks like it bugs when the content is empty => maybe because empty content size fitter ?
	if button(ctx, label, UI_Vec{200, 20}, nil, child_id(ui_id))
	{
		folded^ = !folded^;
	}

	if !folded^
	{
		layout := current_layout(ctx)^;
		layout.rect.pos.x += 50;
		layout.rect.size.x -= 50;
		push_layout(ctx, layout);
		add_content_size_fitter(ctx);
	}
	return !folded^;
}

fold_end :: proc(ctx: ^UI_Context)
{
	pop_layout(ctx);
}

push_group :: proc(ctx: ^UI_Context, theme: Rect_Theme, padding: Padding)
{
	push_layout(ctx, current_layout(ctx)^);
	add_content_size_fitter(ctx);
	layout_draw_rect(ctx, {}, {}, theme);
	push_layout(ctx, current_layout(ctx)^);
	current_layout(ctx).rect.pos += padding.top_left;
	current_layout(ctx).rect.size -= padding.top_left;
	add_content_size_fitter(ctx, padding.bottom_right);
}

pop_group :: proc(ctx: ^UI_Context)
{
	pop_layout(ctx);
	pop_layout(ctx);
}
