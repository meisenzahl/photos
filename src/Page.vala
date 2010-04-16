/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class Page : Gtk.ScrolledWindow, SidebarPage {
    private const int CONSIDER_CONFIGURE_HALTED_MSEC = 400;
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    public Gtk.ActionGroup action_group = null;
    public Gtk.ActionGroup common_action_group = null;
    
    private string page_name;
    private ViewCollection view = null;
    private Gtk.Window container = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private string menubar_path = null;
    private SidebarMarker marker = null;
    private Gdk.Rectangle last_position = Gdk.Rectangle();
    private Gtk.Widget event_source = null;
    private bool dnd_enabled = false;
    private bool in_view = false;
    private ulong last_configure_ms = 0;
    private bool report_move_finished = false;
    private bool report_resize_finished = false;
    private Gdk.Point last_down = Gdk.Point();
    private bool is_destroyed = false;
    protected bool ctrl_pressed = false;
    protected bool alt_pressed = false;
    protected bool shift_pressed = false;
    
    public Page(string page_name) {
        this.page_name = page_name;
        this.view = new ViewCollection("ViewCollection for Page %s".printf(page_name));
        
        last_down = { -1, -1 };
        
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);

        popup_menu += on_context_keypress;
    }
    
    ~Page() {
#if TRACE_DTORS
        debug("DTOR: Page %s", page_name);
#endif
    }
    
    private void destroy_ui_manager_widgets(Gtk.UIManagerItemType item_type) {
        SList<weak Gtk.Widget> toplevels = ui.get_toplevels(item_type);
        for (int ctr = 0; ctr < toplevels.length(); ctr++)
            toplevels.nth(ctr).data.destroy();
    }
    
    // This is called by the page controller when it has removed this page ... pages should override
    // this (or the signal) to clean up
    public override void destroy() {
        debug("Page %s Destroyed", get_page_name());

        // untie signals
        detach_event_source();
        view.close();
        
        // remove refs to external objects which may be pointing to the Page
        clear_marker();
        clear_container();
        
        // Without destroying the menubar, Gtk spits out an assertion related to
        // a Gtk.AccelLabel being unable to disconnect a signal from the UI Manager's
        // Gtk.AccelGroup because the AccelGroup has already been finalized.  This only
        // happens during a drag-and-drop operation where the Page is destroyed.
        // Destroying the menubar explicitly solves this problem.  These calls go through and
        // ensure *all* widgets created by the UI manager are destroyed.
        destroy_ui_manager_widgets(Gtk.UIManagerItemType.MENUBAR);
        destroy_ui_manager_widgets(Gtk.UIManagerItemType.TOOLBAR);
        destroy_ui_manager_widgets(Gtk.UIManagerItemType.POPUP);
        
        // toolbars (as of yet) are not created by the UI Manager and need to be destroyed
        // explicitly
        toolbar.destroy();

        is_destroyed = true;
        
        base.destroy();
    }
    
    public string get_page_name() {
        return page_name;
    }
    
    public virtual void set_page_name(string page_name) {
        this.page_name = page_name;
    }
    
    public ViewCollection get_view() {
        return view;
    }
    
    // Usually when a controller is needed to iterate through a page's ViewCollection, the page's
    // own ViewCollection is the right choice.  Some pages may keep their own ViewCollection but
    // are actually referring to another ViewController for input (such as PhotoPage, whose own
    // ViewCollection merely refers to what's currently on the page while it uses another 
    // ViewController to flip through a collection of thumbnails).
    public virtual ViewCollection get_controller() {
        return view;
    }
    
    public Gtk.Window? get_container() {
        return container;
    }
    
    public virtual void set_container(Gtk.Window container) {
        assert(this.container == null);
        
        this.container = container;
    }
    
    public virtual void clear_container() {
        container = null;
    }
    
    public void set_event_source(Gtk.Widget event_source) {
        assert(this.event_source == null);

        this.event_source = event_source;
        event_source.set_flags(Gtk.WidgetFlags.CAN_FOCUS);

        // interested in mouse button and motion events on the event source
        event_source.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.POINTER_MOTION_HINT_MASK
            | Gdk.EventMask.BUTTON_MOTION_MASK);
        event_source.button_press_event += on_button_pressed_internal;
        event_source.button_release_event += on_button_released_internal;
        event_source.motion_notify_event += on_motion_internal;
    }
    
    private void detach_event_source() {
        if (event_source == null)
            return;
        
        event_source.button_press_event -= on_button_pressed_internal;
        event_source.button_release_event -= on_button_released_internal;
        event_source.motion_notify_event -= on_motion_internal;
        
        disable_drag_source();
        
        event_source = null;
    }
    
    public Gtk.Widget? get_event_source() {
        return event_source;
    }
    
    public string get_sidebar_text() {
        return page_name;
    }
    
    public void set_marker(SidebarMarker marker) {
        this.marker = marker;
    }
    
    public SidebarMarker? get_marker() {
        return marker;
    }
    
    public void clear_marker() {
        marker = null;
    }
    
    public virtual Gtk.MenuBar get_menubar() {
        assert(menubar_path != null);
        
        return (Gtk.MenuBar) ui.get_widget(menubar_path);
    }

    public virtual Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public virtual Gtk.Menu? get_page_context_menu() {
        return null;
    }
    
    public virtual void switching_from() {
        in_view = false;
    }
    
    public virtual void switched_to() {
        in_view = true;
        update_modifiers();
    }
    
    public bool is_in_view() {
        return in_view;
    }
    
    public virtual void switching_to_fullscreen() {
    }
    
    public virtual void returning_from_fullscreen() {
    }
    
    public void set_item_sensitive(string path, bool sensitive) {
        Gtk.Widget widget = ui.get_widget(path);
        if (widget == null) {
            critical("No widget for UI element %s", path);
            
            return;
        }
        
        widget.sensitive = sensitive;
    }
    
    public void set_item_display(string path, string? label, string? tooltip, bool sensitive) {
        Gtk.Action? action = ui.get_action(path);
        if (action == null) {
            critical("No action for UI element %s", path);
            
            return;
        }
        
        if (label != null)
            action.label = label;
        
        if (tooltip != null)
            action.tooltip = tooltip;
        
        action.sensitive = sensitive;
    }
    
    public void set_action_sensitive(string name, bool sensitive) {
        Gtk.Action action = action_group.get_action(name);
        if (action == null) {
            warning("Page %s: Unable to locate action %s", get_page_name(), name);
            
            return;
        }
        
        action.sensitive = sensitive;
    }
    
    private void get_modifiers(out bool ctrl, out bool alt, out bool shift) {
            int x, y;
        Gdk.ModifierType mask;
        AppWindow.get_instance().window.get_pointer(out x, out y, out mask);

        ctrl = (mask & Gdk.ModifierType.CONTROL_MASK) != 0;
        alt = (mask & Gdk.ModifierType.MOD1_MASK) != 0;
        shift = (mask & Gdk.ModifierType.SHIFT_MASK) != 0;
    }

    private virtual void update_modifiers() {
        bool ctrl_currently_pressed, alt_currently_pressed, shift_currently_pressed;
        get_modifiers(out ctrl_currently_pressed, out alt_currently_pressed,
            out shift_currently_pressed);
        
        if (ctrl_pressed && !ctrl_currently_pressed)
            on_ctrl_released(null);
        else if (!ctrl_pressed && ctrl_currently_pressed)
            on_ctrl_pressed(null);

        if (alt_pressed && !alt_currently_pressed)
            on_alt_released(null);
        else if (!alt_pressed && alt_currently_pressed)
            on_alt_pressed(null);

        if (shift_pressed && !shift_currently_pressed)
            on_shift_released(null);
        else if (!shift_pressed && shift_currently_pressed)
            on_shift_pressed(null);
    }
    
    public PageWindow? get_page_window() {
        Gtk.Widget p = parent;
        while (p != null) {
            if (p is PageWindow)
                return (PageWindow) p;
            
            p = p.parent;
        }
        
        return null;
    }
    
    public CommandManager get_command_manager() {
        return AppWindow.get_command_manager();
    }
    
    private void decorate_command_manager_item(string path, string prefix, string default_explanation,
        CommandDescription? desc) {
        set_item_sensitive(path, desc != null);
        
        Gtk.Action action = ui.get_action(path);
        if (desc != null) {
            action.label = "%s %s".printf(prefix, desc.get_name());
            action.tooltip = desc.get_explanation();
        } else {
            action.label = prefix;
            action.tooltip = default_explanation;
        }
    }
    
    public void decorate_undo_item(string path) {
        decorate_command_manager_item(path, Resources.UNDO_MENU, Resources.UNDO_TOOLTIP,
            AppWindow.get_command_manager().get_undo_description());
    }
    
    public void decorate_redo_item(string path) {
        decorate_command_manager_item(path, Resources.REDO_MENU, Resources.REDO_TOOLTIP,
            AppWindow.get_command_manager().get_redo_description());
    }
    
    protected void init_ui(string ui_filename, string? menubar_path, string action_group_name, 
        Gtk.ActionEntry[]? entries = null, Gtk.ToggleActionEntry[]? toggle_entries = null) {
        init_ui_start(ui_filename, action_group_name, entries, toggle_entries);
        init_ui_bind(menubar_path);
    }
    
    protected void init_load_ui(string ui_filename) {
        File ui_file = Resources.get_ui(ui_filename);

        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error gle) {
            error("Error loading UI file %s: %s", ui_file.get_path(), gle.message);
        }
    }
    
    protected void init_ui_start(string ui_filename, string action_group_name,
        Gtk.ActionEntry[]? entries = null, Gtk.ToggleActionEntry[]? toggle_entries = null) {
        init_load_ui(ui_filename);

        action_group = new Gtk.ActionGroup(action_group_name);
        if (entries != null)
            action_group.add_actions(entries, this);
        if (toggle_entries != null)
            action_group.add_toggle_actions(toggle_entries, this);
    }
    
    protected virtual void init_actions(int selected_count, int count) {
    }
    
    protected void init_ui_bind(string? menubar_path) {
        this.menubar_path = menubar_path;
        
        ui.insert_action_group(action_group, 0);
        
        common_action_group = new Gtk.ActionGroup("CommonActionGroup");
        AppWindow.get_instance().add_common_actions(common_action_group);
        ui.insert_action_group(common_action_group, 0);
        
        ui.ensure_update();
        
        init_actions(get_view().get_selected_count(), get_view().get_count());
    }
    
    // This method enables drag-and-drop on the event source and routes its events through this
    // object
    public void enable_drag_source(Gdk.DragAction actions, Gtk.TargetEntry[] source_target_entries) {
        if (dnd_enabled)
            return;
            
        assert(event_source != null);
        
        Gtk.drag_source_set(event_source, Gdk.ModifierType.BUTTON1_MASK, source_target_entries, actions);
        
        // hook up handlers which route the event_source's DnD signals to the Page's (necessary
        // because Page is a NO_WINDOW widget and cannot support DnD on its own).
        event_source.drag_begin += on_drag_begin;
        event_source.drag_data_get += on_drag_data_get;
        event_source.drag_data_delete += on_drag_data_delete;
        event_source.drag_end += on_drag_end;
        event_source.drag_failed += on_drag_failed;
        
        dnd_enabled = true;
    }
    
    public void disable_drag_source() {
        if (!dnd_enabled)
            return;

        assert(event_source != null);
        
        event_source.drag_begin -= on_drag_begin;
        event_source.drag_data_get -= on_drag_data_get;
        event_source.drag_data_delete -= on_drag_data_delete;
        event_source.drag_end -= on_drag_end;
        event_source.drag_failed -= on_drag_failed;
        Gtk.drag_source_unset(event_source);
        
        dnd_enabled = false;
    }
    
    public bool is_dnd_enabled() {
        return dnd_enabled;
    }
    
    private void on_drag_begin(Gdk.DragContext context) {
        drag_begin(context);
    }
    
    private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint info, uint time) {
        drag_data_get(context, selection_data, info, time);
    }
    
    private void on_drag_data_delete(Gdk.DragContext context) {
        drag_data_delete(context);
    }
    
    private void on_drag_end(Gdk.DragContext context) {
        drag_end(context);
    }
    
    // wierdly, Gtk 2.16.1 doesn't supply a drag_failed virtual method in the GtkWidget impl ...
    // Vala binds to it, but it's not available in gtkwidget.h, and so gcc complains.  Have to
    // makeshift one for now.
    // https://bugzilla.gnome.org/show_bug.cgi?id=584247
    public virtual bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        return false;
    }
    
    private bool on_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        return source_drag_failed(context, drag_result);
    }
    
    // Use this function rather than GDK or GTK's get_pointer, especially if called during a 
    // button-down mouse drag (i.e. a window grab).
    //
    // For more information, see: https://bugzilla.gnome.org/show_bug.cgi?id=599937
    public bool get_event_source_pointer(out int x, out int y, out Gdk.ModifierType mask) {
        if (event_source == null)
            return false;
        
        event_source.window.get_pointer(out x, out y, out mask);
        
        if (last_down.x < 0 || last_down.y < 0)
            return true;
            
        // check for bogus values inside a drag which goes outside the window
        // caused by (most likely) X windows signed 16-bit int overflow and fixup
        // (https://bugzilla.gnome.org/show_bug.cgi?id=599937)
        
        if ((x - last_down.x).abs() >= 0x7FFF)
            x += 0xFFFF;
        
        if ((y - last_down.y).abs() >= 0x7FFF)
            y += 0xFFFF;
        
        return true;
    }
    
    protected virtual bool on_left_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_middle_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_right_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_left_released(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_middle_released(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_right_released(Gdk.EventButton event) {
        return false;
    }
    
    private bool on_button_pressed_internal(Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                if (event_source != null)
                    event_source.grab_focus();
                
                // stash location of mouse down for drag fixups
                last_down.x = (int) event.x;
                last_down.y = (int) event.y;
                
                return on_left_click(event);

            case 2:
                return on_middle_click(event);
            
            case 3:
                return on_right_click(event);
            
            default:
                return false;
        }
    }
    
    private bool on_button_released_internal(Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                // clear when button released, only for drag fixups
                last_down = { -1, -1 };
                
                return on_left_released(event);
            
            case 2:
                return on_middle_released(event);
            
            case 3:
                return on_right_released(event);
            
            default:
                return false;
        }
    }

    protected virtual bool on_ctrl_pressed(Gdk.EventKey? event) {
        return false;
    }
    
    protected virtual bool on_ctrl_released(Gdk.EventKey? event) {
        return false;
    }
    
    protected virtual bool on_alt_pressed(Gdk.EventKey? event) {
        return false;
    }
    
    protected virtual bool on_alt_released(Gdk.EventKey? event) {
        return false;
    }
    
    protected virtual bool on_shift_pressed(Gdk.EventKey? event) {
        return false;
    }
    
    protected virtual bool on_shift_released(Gdk.EventKey? event) {
        return false;
    }
    
    protected virtual bool on_app_key_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_app_key_released(Gdk.EventKey event) {
        return false;
    }
    
    public bool notify_app_key_pressed(Gdk.EventKey event) {
        bool ctrl_currently_pressed, alt_currently_pressed, shift_currently_pressed;
        get_modifiers(out ctrl_currently_pressed, out alt_currently_pressed,
            out shift_currently_pressed);

        switch (Gdk.keyval_name(event.keyval)) {
            case "Control_L":
            case "Control_R":
                if (!ctrl_currently_pressed || ctrl_pressed)
                    return false;

                ctrl_pressed = true;
                
                return on_ctrl_pressed(event);

            case "Meta_L":
            case "Meta_R":
            case "Alt_L":
            case "Alt_R":
                if (!alt_currently_pressed || alt_pressed)
                    return false;

                alt_pressed = true;
                
                return on_alt_pressed(event);
            
            case "Shift_L":
            case "Shift_R":
                if (!shift_currently_pressed || shift_pressed)
                    return false;

                shift_pressed = true;
                
                return on_shift_pressed(event);
        }
        
        return on_app_key_pressed(event);
    }
    
    public bool notify_app_key_released(Gdk.EventKey event) {
        bool ctrl_currently_pressed, alt_currently_pressed, shift_currently_pressed;
        get_modifiers(out ctrl_currently_pressed, out alt_currently_pressed,
            out shift_currently_pressed);

        switch (Gdk.keyval_name(event.keyval)) {
            case "Control_L":
            case "Control_R":
                if (ctrl_currently_pressed || !ctrl_pressed)
                    return false;

                ctrl_pressed = false;
                
                return on_ctrl_released(event);
            
            case "Meta_L":
            case "Meta_R":
            case "Alt_L":
            case "Alt_R":
                if (alt_currently_pressed || !alt_pressed)
                    return false;

                alt_pressed = false;
                
                return on_alt_released(event);
            
            case "Shift_L":
            case "Shift_R":
                if (shift_currently_pressed || !shift_pressed)
                    return false;

                shift_pressed = false;
                
                return on_shift_released(event);
        }
        
        return on_app_key_released(event);
    }

    public bool notify_app_focus_in(Gdk.EventFocus event) {
        update_modifiers();
        
        return false;
    }

    public bool notify_app_focus_out(Gdk.EventFocus event) {
        return false;
    }
    
    protected virtual void on_move(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_move_start(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_move_finished(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize_start(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize_finished(Gdk.Rectangle rect) {
    }
    
    protected virtual bool on_configure(Gdk.EventConfigure event, Gdk.Rectangle rect) {
        return false;
    }
    
    public bool notify_configure_event(Gdk.EventConfigure event) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = event.x;
        rect.y = event.y;
        rect.width = event.width;
        rect.height = event.height;
        
        // special case events, to report when a configure first starts (and appears to end)
        if (last_configure_ms == 0) {
            if (last_position.x != rect.x || last_position.y != rect.y) {
                on_move_start(rect);
                report_move_finished = true;
            }
            
            if (last_position.width != rect.width || last_position.height != rect.height) {
                on_resize_start(rect);
                report_resize_finished = true;
            }

            // need to check more often then the timeout, otherwise it could be up to twice the
            // wait time before it's noticed
            Timeout.add(CONSIDER_CONFIGURE_HALTED_MSEC / 8, check_configure_halted);
        }
        
        if (last_position.x != rect.x || last_position.y != rect.y)
            on_move(rect);
        
        if (last_position.width != rect.width || last_position.height != rect.height)
            on_resize(rect);
        
        last_position = rect;
        last_configure_ms = now_ms();

        return on_configure(event, rect);
    }
    
    private bool check_configure_halted() {
        if (is_destroyed)
            return false;

        if ((now_ms() - last_configure_ms) < CONSIDER_CONFIGURE_HALTED_MSEC)
            return true;
        
        if (report_move_finished)
            on_move_finished((Gdk.Rectangle) allocation);
        
        if (report_resize_finished)
            on_resize_finished((Gdk.Rectangle) allocation);
        
        last_configure_ms = 0;
        report_move_finished = false;
        report_resize_finished = false;
        
        return false;
    }
    
    protected virtual bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        return false;
    }
    
    private bool on_motion_internal(Gdk.EventMotion event) {
        int x, y;
        Gdk.ModifierType mask;
        if (event.is_hint) {
            get_event_source_pointer(out x, out y, out mask);
        } else {
            x = (int) event.x;
            y = (int) event.y;
            mask = event.state;
        }
        
        return on_motion(event, x, y, mask);
    }

    protected virtual bool on_context_keypress() {
        return false;
    }
    
    protected virtual bool on_context_buttonpress(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_context_invoked() {
        return true;
    }

    protected bool popup_context_menu(Gtk.Menu? context_menu,
        Gdk.EventButton? event = null) {
        on_context_invoked();

        if (context_menu == null)
            return false;

        if (event == null)
            context_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
        else
            context_menu.popup(null, null, null, event.button, event.time);

        return true;
    }
}

public abstract class CheckerboardPage : Page {
    private const int AUTOSCROLL_PIXELS = 50;
    private const int AUTOSCROLL_TICKS_MSEC = 50;
    
    private CheckerboardLayout layout;
    private Gtk.Menu item_context_menu = null;
    private Gtk.Menu page_context_menu = null;
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    protected CheckerboardItem anchor = null;
    protected CheckerboardItem cursor = null;
    private CheckerboardItem highlighted = null;
    private bool autoscroll_scheduled = false;
    private CheckerboardItem activated_item = null;

    public CheckerboardPage(string page_name) {
        base(page_name);
        
        layout = new CheckerboardLayout(get_view());
        layout.set_name(page_name);
        
        set_event_source(layout);

        set_border_width(0);
        set_shadow_type(Gtk.ShadowType.NONE);
        
        viewport.set_border_width(0);
        viewport.set_shadow_type(Gtk.ShadowType.NONE);
        
        viewport.add(layout);
        
        // want to set_adjustments before adding to ScrolledWindow to let our signal handlers
        // run first ... otherwise, the thumbnails draw late
        layout.set_adjustments(get_hadjustment(), get_vadjustment());
        
        add(viewport);
        
        // need to monitor items going hidden when dealing with anchor/cursor/highlighted items
        get_view().items_hidden += on_items_hidden;
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
    }
    
    public void init_item_context_menu(string path) {
        item_context_menu = (Gtk.Menu) ui.get_widget(path);
    }

    public void init_page_context_menu(string path) {
        page_context_menu = (Gtk.Menu) ui.get_widget(path);
    }
   
    public Gtk.Menu? get_context_menu() {
        // show page context menu if nothing is selected
        return (get_view().get_selected_count() != 0) ? get_item_context_menu() : get_page_context_menu();
    }
    
    public virtual Gtk.Menu? get_item_context_menu() {
        return item_context_menu;
    }
    
    public override Gtk.Menu? get_page_context_menu() {
        return page_context_menu;
    }
    
    protected override bool on_context_keypress() {
        return popup_context_menu(get_context_menu());
    }
    
    protected virtual void on_item_activated(CheckerboardItem item) {
    }
    
    public CheckerboardLayout get_checkerboard_layout() {
        return layout;
    }
    
    public override void switching_from() {
        layout.set_in_view(false);

        // unselect everything so selection won't persist after page loses focus 
        get_view().unselect_all();
        
        base.switching_from();
    }
    
    public override void switched_to() {
        layout.set_in_view(true);       

        base.switched_to();
    }
    
    public abstract CheckerboardItem? get_fullscreen_photo();
    
    public void set_page_message(string message) {
        layout.set_message(message);
        if (is_in_view())
            layout.queue_draw();
    }
    
    public override void set_page_name(string name) {
        base.set_page_name(name);
        
        layout.set_name(name);
    }
    
    public CheckerboardItem? get_item_at_pixel(double x, double y) {
        return layout.get_item_at_pixel(x, y);
    }
    
    private void on_items_hidden(Gee.Iterable<DataView> hidden) {
        foreach (DataView view in hidden) {
            CheckerboardItem item = (CheckerboardItem) view;
            
            if (anchor == item)
                anchor = null;
            
            if (cursor == item)
                cursor = null;
            
            if (highlighted == item)
                highlighted = null;
        }
    }

    protected override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;

        // mask out the modifiers we're interested in
        uint state = event.state & Gdk.ModifierType.SHIFT_MASK;

        switch (Gdk.keyval_name(event.keyval)) {
            case "Up":
            case "KP_Up":
                move_cursor(CompassPoint.NORTH);
                select_anchor_to_cursor(state);
            break;
            
            case "Down":
            case "KP_Down":
                move_cursor(CompassPoint.SOUTH);
                select_anchor_to_cursor(state);
            break;
            
            case "Left":
            case "KP_Left":
                move_cursor(CompassPoint.WEST);
                select_anchor_to_cursor(state);
            break;
            
            case "Right":
            case "KP_Right":
                move_cursor(CompassPoint.EAST);
                select_anchor_to_cursor(state);
            break;
            
            case "Home":
            case "KP_Home":
                CheckerboardItem? first = (CheckerboardItem?) get_view().get_first();
                if (first != null)
                    cursor_to_item(first);
                select_anchor_to_cursor(state);
            break;
            
            case "End":
            case "KP_End":
                CheckerboardItem? last = (CheckerboardItem?) get_view().get_last();
                if (last != null)
                    cursor_to_item(last);
                select_anchor_to_cursor(state);
            break;
            
            case "Return":
            case "KP_Enter":
                if (get_view().get_selected_count() == 1)
                    on_item_activated((CheckerboardItem) get_view().get_selected_at(0));
                else
                    handled = false;
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }
    
    protected override bool on_left_click(Gdk.EventButton event) {
        // only interested in single-click and double-clicks for now
        if ((event.type != Gdk.EventType.BUTTON_PRESS) && (event.type != Gdk.EventType.2BUTTON_PRESS))
            return false;
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        // use clicks for multiple selection and activation only; single selects are handled by
        // button release, to allow for multiple items to be selected then dragged
        CheckerboardItem item = get_item_at_pixel(event.x, event.y);
        if (item != null) {
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    Marker marker = get_view().mark(item);
                    get_view().toggle_marked(marker);

                    if (item.is_selected()) {
                        anchor = item;
                        cursor = item;
                    }
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    get_view().unselect_all();
                    
                    if (anchor == null)
                        anchor = item;
                    
                    select_between_items(anchor, item);
                    
                    cursor = item;
                break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                default:
                    if (event.type == Gdk.EventType.2BUTTON_PRESS) {
                        activated_item = item;
                    } else {
                        // if the user has selected one or more items and is preparing for a drag,
                        // don't want to blindly unselect: if they've clicked on an unselected item
                        // unselect all and select that one; if they've clicked on a previously
                        // selected item, do nothing
                        if (!item.is_selected()) {
                            get_view().unselect_all();
                            get_view().select_marked(get_view().mark(item));
                        }
                    }

                    anchor = item;
                    cursor = item;
                break;
            }
        } else {
            // user clicked on "dead" area
            get_view().unselect_all();
        }

        // need to determine if the signal should be passed to the DnD handlers
        // Return true to block the DnD handler, false otherwise

        if (item == null) {
            layout.set_drag_select_origin((int) event.x, (int) event.y);

            return true;
        }

        return get_view().get_selected_count() == 0;
    }
    
    protected override bool on_left_released(Gdk.EventButton event) {
        // if drag-selecting, stop here and do nothing else
        if (layout.is_drag_select_active()) {
            layout.clear_drag_select();
            anchor = cursor;

            return true;
        }
        
        // only interested in non-modified button releases
        if ((event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) != 0)
            return false;
        
        // if the item was activated in the double-click, report it now
        if (activated_item != null) {
            on_item_activated(activated_item);
            activated_item = null;
            
            return true;
        }
        
        CheckerboardItem item = get_item_at_pixel(event.x, event.y);
        if (item == null) {
            // released button on "dead" area
            return true;
        }

        if (cursor != item) {
            // user released mouse button after moving it off the initial item, or moved from dead
            // space onto one.  either way, unselect everything
            get_view().unselect_all();
        } else {
            // the idea is, if a user single-clicks on an item with no modifiers, then all other items
            // should be deselected, however, if they single-click in order to drag one or more items,
            // they should remain selected, hence performing this here rather than on_left_click
            // (item may not be selected if an unimplemented modifier key was used)
            if (item.is_selected())
                get_view().unselect_all_but(item);
        }

        return true;
    }
    
    protected override bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS)
            return false;
        
        // get what's right-clicked upon
        CheckerboardItem item = get_item_at_pixel(event.x, event.y);
        if (item != null) {
            // mask out the modifiers we're interested in
            switch (event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // chosen item is toggled
                    Marker marker = get_view().mark(item);
                    get_view().toggle_marked(marker);
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                default:
                    // if the item is already selected, proceed; if item is not selected, a bare right
                    // click unselects everything else but it
                    if (!item.is_selected()) {
                        get_view().unselect_all();
                        
                        Marker marker = get_view().mark(item);
                        get_view().select_marked(marker);
                    }
                break;
            }
        } else {
            // clicked in "dead" space, unselect everything
            get_view().unselect_all();
        }
       
        Gtk.Menu context_menu = get_context_menu();
        if (context_menu == null)
            return false;

        if (!on_context_invoked())
            return false;

        context_menu.popup(null, null, null, event.button, event.time);

        return true;
    }
    
    protected virtual bool on_mouse_over(CheckerboardItem? item, int x, int y, Gdk.ModifierType mask) {
        // if hovering over the last hovered item, or both are null (nothing highlighted and
        // hovering over empty space), do nothing
        if (item == highlighted)
            return true;
        
        // either something new is highlighted or now hovering over empty space, so dim old item
        if (highlighted != null) {
            highlighted.unbrighten();
            highlighted = null;
        }
        
        // if over empty space, done
        if (item == null)
            return true;
        
        // brighten the new item
        item.brighten();
        highlighted = item;
        
        return true;
    }
    
    protected override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        // report what item the mouse is hovering over
        if (!on_mouse_over(get_item_at_pixel(x, y), x, y, mask))
            return false;
        
        // go no further if not drag-selecting
        if (!layout.is_drag_select_active())
            return false;
        
        // set the new endpoint of the drag selection
        layout.set_drag_select_endpoint(x, y);
        
        updated_selection_band();

        // if out of bounds, schedule a check to auto-scroll the viewport
        if (!autoscroll_scheduled 
            && get_adjustment_relation(get_vadjustment(), y) != AdjustmentRelation.IN_RANGE) {
            Timeout.add(AUTOSCROLL_TICKS_MSEC, selection_autoscroll);
            autoscroll_scheduled = true;
        }

        return true;
    }
    
    private void updated_selection_band() {
        assert(layout.is_drag_select_active());
        
        // get all items inside the selection
        Gee.List<CheckerboardItem>? intersection = layout.items_in_selection_band();
        if (intersection == null)
            return;

        // unselect everything not in the intersection
        Marker marker = get_view().start_marking();
        foreach (DataView view in get_view().get_selected()) {
            CheckerboardItem item = (CheckerboardItem) view;
            
            if (!intersection.contains(item))
                marker.mark(item);
        }
        
        get_view().unselect_marked(marker);
        
        // select everything in the intersection and update the cursor
        marker = get_view().start_marking();
        cursor = null;
        foreach (CheckerboardItem item in intersection) {
            marker.mark(item);
            if (cursor == null)
                cursor = item;
        }
        
        get_view().select_marked(marker);
    }
    
    private bool selection_autoscroll() {
        if (!layout.is_drag_select_active()) { 
            autoscroll_scheduled = false;
            
            return false;
        }
        
        // as the viewport never scrolls horizontally, only interested in vertical
        Gtk.Adjustment vadj = get_vadjustment();
        
        int x, y;
        Gdk.ModifierType mask;
        get_event_source_pointer(out x, out y, out mask);
        
        int new_value = (int) vadj.get_value();
        switch (get_adjustment_relation(vadj, y)) {
            case AdjustmentRelation.BELOW:
                // pointer above window, scroll up
                new_value -= AUTOSCROLL_PIXELS;
                layout.set_drag_select_endpoint(x, new_value);
            break;
            
            case AdjustmentRelation.ABOVE:
                // pointer below window, scroll down, extend selection to bottom of page
                new_value += AUTOSCROLL_PIXELS;
                layout.set_drag_select_endpoint(x, new_value + (int) vadj.get_page_size());
            break;
            
            case AdjustmentRelation.IN_RANGE:
                autoscroll_scheduled = false;
                
                return false;
            
            default:
                warn_if_reached();
            break;
        }
        
        // It appears that in GTK+ 2.18, the adjustment is not clamped the way it was in 2.16.
        // This may have to do with how adjustments are different w/ scrollbars, that they're upper
        // clamp is upper - page_size ... either way, enforce these limits here
        vadj.set_value(new_value.clamp((int) vadj.get_lower(), 
            (int) vadj.get_upper() - (int) vadj.get_page_size()));
        
        updated_selection_band();
        
        return true;
    }
    
    public void cursor_to_item(CheckerboardItem item) {
        assert(get_view().contains(item));

        cursor = item;
        
        get_view().unselect_all();
        
        Marker marker = get_view().mark(item);
        get_view().select_marked(marker);

        // if item is in any way out of view, scroll to it
        Gtk.Adjustment vadj = get_vadjustment();
        if (get_adjustment_relation(vadj, item.allocation.y) == AdjustmentRelation.IN_RANGE
            && (get_adjustment_relation(vadj, item.allocation.y + item.allocation.height) == AdjustmentRelation.IN_RANGE))
            return;

        // scroll to see the new item
        int top = 0;
        if (item.allocation.y < vadj.get_value()) {
            top = item.allocation.y;
            top -= CheckerboardLayout.ROW_GUTTER_PADDING / 2;
        } else {
            top = item.allocation.y + item.allocation.height - (int) vadj.get_page_size();
            top += CheckerboardLayout.ROW_GUTTER_PADDING / 2;
        }
        
        vadj.set_value(top);
    }
    
    public void move_cursor(CompassPoint point) {
        // if no items, nothing to do
        if (get_view().get_count() == 0)
            return;
            
        // if nothing is selected, simply select the first and exit
        if (get_view().get_selected_count() == 0 || cursor == null) {
            CheckerboardItem item = layout.get_item_at_coordinate(0, 0);
            cursor_to_item(item);
            anchor = item;

            return;
        }
               
        // move the cursor relative to the "first" item
        CheckerboardItem? item = layout.get_item_relative_to(cursor, point);
        if (item != null)
            cursor_to_item(item);
   }

    public void select_between_items(CheckerboardItem item_start, CheckerboardItem item_end) {
        Marker marker = get_view().start_marking();

        bool passed_start = false;
        bool passed_end = false;

        foreach (DataObject object in get_view().get_all()) {
            CheckerboardItem item = (CheckerboardItem) object;
            
            if (item_start == item)
                passed_start = true;

            if (item_end == item)
                passed_end = true;

            if (passed_start || passed_end)
                marker.mark((DataView) object);

            if (passed_start && passed_end)
                break;
        }
        
        get_view().select_marked(marker);
    }

    public void select_anchor_to_cursor(uint state) {
        if (cursor == null || anchor == null)
            return;

        if (state == Gdk.ModifierType.SHIFT_MASK) {
            get_view().unselect_all();
            select_between_items(anchor, cursor);
        } else {
            anchor = cursor;
        }
    }

    protected virtual void set_display_titles(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, display);
        get_view().thaw_notifications();
    }
}

public abstract class SinglePhotoPage : Page {
    public const Gdk.InterpType FAST_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    public enum UpdateReason {
        NEW_PIXBUF,
        QUALITY_IMPROVEMENT,
        RESIZED_CANVAS
    }
    
    protected Gdk.GC canvas_gc = null;
    protected Gtk.DrawingArea canvas = new Gtk.DrawingArea();
    protected Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    protected Gdk.GC text_gc = null;
    
    private bool scale_up_to_viewport;
    private Gdk.Pixmap pixmap = null;
    private Dimensions pixmap_dim = Dimensions();
    private Gdk.Pixbuf unscaled = null;
    private Dimensions max_dim = Dimensions();
    private Gdk.Pixbuf scaled = null;
    private Gdk.Rectangle scaled_pos = Gdk.Rectangle();
    private ZoomState static_zoom_state;
    private bool zoom_high_quality = true;
    private ZoomState saved_zoom_state;

    public SinglePhotoPage(string page_name, bool scale_up_to_viewport) {
        base(page_name);
        
        this.scale_up_to_viewport = scale_up_to_viewport;
        
        // With the current code automatically resizing the image to the viewport, scrollbars
        // should never be shown, but this may change if/when zooming is supported
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        set_border_width(0);
        set_shadow_type(Gtk.ShadowType.NONE);
        
        viewport.set_shadow_type(Gtk.ShadowType.NONE);
        viewport.set_border_width(0);
        viewport.add(canvas);
        
        add(viewport);
        
        // turn off double-buffering because all painting happens in pixmap, and is sent to the window
        // wholesale in on_canvas_expose
        canvas.set_double_buffered(false);
        canvas.add_events(Gdk.EventMask.EXPOSURE_MASK | Gdk.EventMask.STRUCTURE_MASK 
            | Gdk.EventMask.SUBSTRUCTURE_MASK);
        
        viewport.size_allocate += on_viewport_resize;
        canvas.expose_event += on_canvas_exposed;

        set_event_source(canvas);
    }

    private void render_zoomed_to_pixmap(ZoomState zoom_state) {
        Gdk.Pixbuf basis_pixbuf = (zoom_high_quality) ? get_zoom_optimized_pixbuf(zoom_state) :
            unscaled;
        if (basis_pixbuf == null)
            basis_pixbuf = unscaled;

        Gdk.Rectangle view_rect = zoom_state.get_viewing_rectangle();
        Gdk.Rectangle view_rect_proj = zoom_state.get_viewing_rectangle_projection(basis_pixbuf);

        Gdk.Pixbuf proj_subpixbuf = new Gdk.Pixbuf.subpixbuf(basis_pixbuf, view_rect_proj.x,
            view_rect_proj.y, view_rect_proj.width, view_rect_proj.height);

        Gdk.Pixbuf zoomed = proj_subpixbuf.scale_simple(view_rect.width, view_rect.height,
            Gdk.InterpType.BILINEAR);

        int draw_x = (pixmap_dim.width - view_rect.width) / 2;
        if (draw_x < 0)
            draw_x = 0;
        int draw_y = (pixmap_dim.height - view_rect.height) / 2;
        if (draw_y < 0)
            draw_y = 0;

        pixmap.draw_pixbuf(canvas_gc, zoomed, 0, 0, draw_x, draw_y, -1, -1, Gdk.RgbDither.NORMAL,
            0, 0);
    }

    protected void on_interactive_zoom(ZoomState interactive_zoom_state) {
        assert(is_zoom_supported());

        pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, -1, -1);
        bool old_quality_setting = zoom_high_quality;
        zoom_high_quality = false;
        render_zoomed_to_pixmap(interactive_zoom_state);
        zoom_high_quality = old_quality_setting;
        canvas.window.draw_drawable(canvas_gc, pixmap, 0, 0, 0, 0, -1, -1);
    }

    protected void on_interactive_pan(ZoomState interactive_zoom_state) {
        assert(is_zoom_supported());

        pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, -1, -1);
        bool old_quality_setting = zoom_high_quality;
        zoom_high_quality = true;
        render_zoomed_to_pixmap(interactive_zoom_state);
        zoom_high_quality = old_quality_setting;
        canvas.window.draw_drawable(canvas_gc, pixmap, 0, 0, 0, 0, -1, -1);
    }

    protected virtual bool is_zoom_supported() {
        return false;
    }

    protected virtual Gdk.Pixbuf? get_zoom_optimized_pixbuf(ZoomState zoom_state) {
        return null;
    }

    protected virtual void cancel_zoom() {
        if (pixmap != null)
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, -1, -1);
    }

    protected virtual void save_zoom_state() {
        saved_zoom_state = static_zoom_state;
    }
    
    protected virtual void restore_zoom_state() {
        static_zoom_state = saved_zoom_state;
    }
    
    protected ZoomState get_saved_zoom_state() {
        return saved_zoom_state;
    }

    protected void set_zoom_state(ZoomState zoom_state) {
        assert(is_zoom_supported());

        static_zoom_state = zoom_state;
    }

    protected ZoomState get_zoom_state() {
        assert(is_zoom_supported());

        return static_zoom_state;
    }

    public override void switched_to() {
        base.switched_to();
        
        if (unscaled != null)
            repaint();
    }
    
    public override void set_container(Gtk.Window container) {
        base.set_container(container);
        
        // scrollbar policy in fullscreen mode needs to be auto/auto, else the pixbuf will shift
        // off the screen
        if (container is FullscreenWindow)
            set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
    }
    
    // max_dim represents the maximum size of the original pixbuf (i.e. pixbuf may be scaled and
    // the caller capable of producing larger ones depending on the viewport size).  max_dim
    // is used when scale_up_to_viewport is set to true.  Pass a Dimensions with no area if
    // max_dim should be ignored (i.e. scale_up_to_viewport is false).
    public void set_pixbuf(Gdk.Pixbuf unscaled, Dimensions max_dim) {       
        static_zoom_state = ZoomState(max_dim, pixmap_dim,
            static_zoom_state.get_interpolation_factor(),
            static_zoom_state.get_viewport_center());

        this.unscaled = unscaled;
        this.max_dim = max_dim;
        scaled = null;
        
        // need to make sure this has happened
        canvas.realize();
        
        repaint();
    }
    
    public void blank_display() {
        unscaled = null;
        max_dim = Dimensions();
        scaled = null;
        pixmap = null;
        
        // this has to have happened
        canvas.realize();
        
        // force a redraw
        invalidate_all();
    }
    
    public Gdk.Drawable? get_drawable() {
        return pixmap;
    }
    
    public Dimensions get_drawable_dim() {
        return pixmap_dim;
    }
    
    public Scaling get_canvas_scaling() {
        return (get_container() is FullscreenWindow) ? Scaling.for_screen(get_container(), scale_up_to_viewport) 
            : Scaling.for_widget(viewport, scale_up_to_viewport);
    }

    public Gdk.Pixbuf? get_unscaled_pixbuf() {
        return unscaled;
    }
    
    public Gdk.Pixbuf? get_scaled_pixbuf() {
        return scaled;
    }
    
    // Returns a rectangle describing the pixbuf in relation to the canvas
    public Gdk.Rectangle get_scaled_pixbuf_position() {
        return scaled_pos;
    }
    
    public bool is_inside_pixbuf(int x, int y) {
        return coord_in_rectangle(x, y, scaled_pos);
    }
    
    public void invalidate(Gdk.Rectangle rect) {
        if (canvas.window != null)
            canvas.window.invalidate_rect(rect, false);
    }
    
    public void invalidate_all() {
        if (canvas.window != null)
            canvas.window.invalidate_rect(null, false);
    }
    
    private void on_viewport_resize() {
        // do fast repaints while resizing
        internal_repaint(true);
    }
    
    private override void on_resize_finished(Gdk.Rectangle rect) {
        base.on_resize_finished(rect);
       
        // when the resize is completed, do a high-quality repaint
        repaint();
    }
    
    private bool on_canvas_exposed(Gdk.EventExpose event) {
        // to avoid multiple exposes
        if (event.count > 0)
            return false;
        
        // draw pixmap onto canvas unless it's not been instantiated, in which case draw black
        // (so either old image or contents of another page is not left on screen)
        if (pixmap != null) {
            canvas.window.draw_drawable(canvas_gc, pixmap, event.area.x, event.area.y, event.area.x, 
                event.area.y, event.area.width, event.area.height);
        } else {
            canvas.window.draw_rectangle(canvas.style.black_gc, true, event.area.x, event.area.y,
                event.area.width, event.area.height);
        }

        return true;
    }
    
    protected virtual void new_drawable(Gdk.GC default_gc, Gdk.Drawable drawable) {
    }
    
    protected virtual void updated_pixbuf(Gdk.Pixbuf pixbuf, UpdateReason reason, Dimensions old_dim) {
    }
    
    protected virtual void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        if (is_zoom_supported() && (!static_zoom_state.is_default())) {
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, -1, -1);
            render_zoomed_to_pixmap(static_zoom_state);
            canvas.window.draw_drawable(canvas_gc, pixmap, 0, 0, 0, 0, -1, -1);
        } else {
            drawable.draw_pixbuf(gc, scaled, 0, 0, scaled_pos.x, scaled_pos.y, -1, -1, 
                Gdk.RgbDither.NORMAL, 0, 0);
        }
    }
    
    public void repaint() {
        internal_repaint(false);
    }
    
    private void internal_repaint(bool fast) {
        // if not in view, assume a full repaint needed in future but do nothing more
        if (!is_in_view()) {
            pixmap = null;
            scaled = null;
            
            return;
        }
        
        // no image or window, no painting
        if (unscaled == null || canvas.window == null)
            return;
        
        int width = viewport.allocation.width;
        int height = viewport.allocation.height;
        
        if (width <= 0 || height <= 0)
            return;
            
        bool new_pixbuf = (scaled == null);
        
        // save if reporting an image being rescaled
        Dimensions old_scaled_dim = Dimensions.for_rectangle(scaled_pos);

        // attempt to reuse pixmap
        if (pixmap_dim.width != width || pixmap_dim.height != height)
            pixmap = null;
        
        // if necessary, create a pixmap as large as the entire viewport
        bool new_pixmap = false;
        if (pixmap == null) {
            init_pixmap(width, height);
            new_pixmap = true;
        }
        
        if (new_pixbuf || new_pixmap) {
            Dimensions unscaled_dim = Dimensions.for_pixbuf(unscaled);
            
            // determine scaled size of pixbuf ... if a max dimensions is set and not scaling up,
            // respect it
            Dimensions scaled_dim = Dimensions();
            if (!scale_up_to_viewport && max_dim.has_area() && max_dim.width < width && max_dim.height < height)
                scaled_dim = max_dim;
            else
                scaled_dim = unscaled_dim.get_scaled_proportional(pixmap_dim);
            
            assert(width >= scaled_dim.width);
            assert(height >= scaled_dim.height);

            // center pixbuf on the canvas
            scaled_pos.x = (width - scaled_dim.width) / 2;
            scaled_pos.y = (height - scaled_dim.height) / 2;
            scaled_pos.width = scaled_dim.width;
            scaled_pos.height = scaled_dim.height;

            // draw background
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, width, height);
        }
        
        Gdk.InterpType interp = (fast) ? FAST_INTERP : QUALITY_INTERP;
        
        // rescale if canvas rescaled or better quality is requested
        if (scaled == null) {
            scaled = resize_pixbuf(unscaled, Dimensions.for_rectangle(scaled_pos), interp);
            
            UpdateReason reason = UpdateReason.RESIZED_CANVAS;
            if (new_pixbuf)
                reason = UpdateReason.NEW_PIXBUF;
            else if (!new_pixmap && interp == QUALITY_INTERP)
                reason = UpdateReason.QUALITY_IMPROVEMENT;

            static_zoom_state = ZoomState(max_dim, pixmap_dim,
                static_zoom_state.get_interpolation_factor(),
                static_zoom_state.get_viewport_center());

            updated_pixbuf(scaled, reason, old_scaled_dim);
        }

        zoom_high_quality = !fast;
        paint(canvas_gc, pixmap);

        // invalidate everything
        invalidate_all();
    }
    
    private void init_pixmap(int width, int height) {
        assert(unscaled != null);
        assert(canvas.window != null);
        
        pixmap = new Gdk.Pixmap(canvas.window, width, height, -1);
        pixmap_dim = Dimensions(width, height);
        
        // need a new pixbuf to fit this scale
        scaled = null;

        // GC for drawing on the pixmap
        canvas_gc = canvas.style.fg_gc[(int) Gtk.StateType.NORMAL];

        // GC for text
        text_gc = canvas.style.white_gc;

        // no need to resize canvas, viewport does that automatically

        new_drawable(canvas_gc, pixmap);
    }

    protected override bool on_context_keypress() {
        return popup_context_menu(get_page_context_menu());
    }
}

//
// DragPhotoHandler attaches signals to a Page so properly handle drag-and-drop requests for the
// Page as a DnD Source.  (DnD Destination handling is handled by the appropriate AppWindow, i.e.
// LibraryWindow and DirectWindow).
//
// The Page's ViewCollection *must* be holding TransformablePhotos or the show is off.
//
public class PhotoDragAndDropHandler {
    private enum TargetType {
        XDS,
        PHOTO_LIST
    }
    
    private const Gtk.TargetEntry[] SOURCE_TARGET_ENTRIES = {
        { "XdndDirectSave0", Gtk.TargetFlags.OTHER_APP, TargetType.XDS },
        { "shotwell/photo-id", Gtk.TargetFlags.SAME_APP, TargetType.PHOTO_LIST }
    };
    
    private static Gdk.Atom? XDS_ATOM = null;
    private static Gdk.Atom? TEXT_ATOM = null;
    private static uchar[]? XDS_FAKE_TARGET = null;
    
    private weak Page page;
    private Gtk.Widget event_source;
    private File? drag_destination = null;
    
    public PhotoDragAndDropHandler(Page page) {
        this.page = page;
        this.event_source = page.get_event_source();
        assert(event_source != null);
        assert((event_source.flags & Gtk.WidgetFlags.NO_WINDOW) == 0);
        
        // Need to do this because static member variables are not properly handled
        if (XDS_ATOM == null)
            XDS_ATOM = Gdk.Atom.intern_static_string("XdndDirectSave0");
        
        if (TEXT_ATOM == null)
            TEXT_ATOM = Gdk.Atom.intern_static_string("text/plain");
        
        if (XDS_FAKE_TARGET == null)
            XDS_FAKE_TARGET = string_to_uchar_array("shotwell.txt");
        
        // register what's available on this DnD Source
        Gtk.drag_source_set(event_source, Gdk.ModifierType.BUTTON1_MASK, SOURCE_TARGET_ENTRIES,
            Gdk.DragAction.COPY);
        
        // attach to the event source's DnD signals, not the Page's, which is a NO_WINDOW widget
        // and does not emit them
        event_source.drag_begin += on_drag_begin;
        event_source.drag_data_get += on_drag_data_get;
        event_source.drag_end += on_drag_end;
        event_source.drag_failed += on_drag_failed;
    }
    
    ~PhotoDragAndDropHandler() {
        if (event_source != null) {
            event_source.drag_begin -= on_drag_begin;
            event_source.drag_data_get -= on_drag_data_get;
            event_source.drag_end -= on_drag_end;
            event_source.drag_failed -= on_drag_failed;
        }
        
        page = null;
        event_source = null;
    }
    
    private void on_drag_begin(Gdk.DragContext context) {
        debug("on_drag_begin (%s)", page.get_page_name());
        
        if (page == null || page.get_view().get_selected_count() == 0)
            return;
        
        drag_destination = null;
        
        // use the first photo as the icon
        TransformablePhoto photo = (TransformablePhoto) page.get_view().get_selected_at(0).get_source();
        
        try {
            Gdk.Pixbuf icon = photo.get_thumbnail(AppWindow.DND_ICON_SCALE);
            Gtk.drag_source_set_icon_pixbuf(event_source, icon);
        } catch (Error err) {
            warning("Unable to fetch icon for drag-and-drop from %s: %s", photo.to_string(),
                err.message);
        }
        
        // set the XDS property to indicate an XDS save is available
        Gdk.property_change(context.source_window, XDS_ATOM, TEXT_ATOM, 8, Gdk.PropMode.REPLACE,
            XDS_FAKE_TARGET, XDS_FAKE_TARGET.length);
    }
    
    private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        debug("on_drag_data_get (%s)", page.get_page_name());
        
        if (page == null || page.get_view().get_selected_count() == 0)
            return;
        
        switch (target_type) {
            case TargetType.XDS:
                // Fetch the XDS property that has been set with the destination path
                uchar[] data = new uchar[4096];
                Gdk.Atom actual_type;
                int actual_format = 0;
                int actual_length = 0;
                bool fetched = Gdk.property_get(context.source_window, XDS_ATOM, TEXT_ATOM,
                    0, data.length, 0, out actual_type, out actual_format, out data);
                
                // the destination path is actually for our XDS_FAKE_TARGET, use its parent
                // to determine where the file(s) should go
                if (fetched && actual_length > 0)
                    drag_destination = File.new_for_uri(uchar_array_to_string(data, actual_length)).get_parent();
                
                debug("on_drag_data_get (%s): %s", page.get_page_name(),
                    (drag_destination != null) ? drag_destination.get_path() : "(no path)");
                
                // Set the property to "S" for Success or "E" for Error
                selection_data.set(XDS_ATOM, 8,
                    string_to_uchar_array((drag_destination != null) ? "S" : "E"));
            break;
            
            case TargetType.PHOTO_LIST:
                Gee.Collection<TransformablePhoto> sources =
                    (Gee.Collection<TransformablePhoto>) page.get_view().get_selected_sources();
                
                // convert the selected sources to serialized PhotoIDs for internal drag-and-drop
                selection_data.set(Gdk.Atom.intern_static_string("PhotoID"), (int) sizeof(int64),
                    serialize_photo_ids(sources));
            break;
            
            default:
                warning("on_drag_data_get (%s): unknown target type %u", page.get_page_name(),
                    target_type);
            break;
        }
    }
    
    private void on_drag_end() {
        debug("on_drag_end (%s)", page.get_page_name());
        
        if (page == null || page.get_view().get_selected_count() == 0 || drag_destination == null)
            return;
        
        debug("Exporting to %s", drag_destination.get_path());
        
        if (drag_destination.get_path() != null) {
            ExportUI.export_photos(drag_destination,
                (Gee.Collection<TransformablePhoto>) page.get_view().get_selected_sources());
        } else {
            AppWindow.error_message(_("Photos cannot be exported to this directory."));
        }
        
        drag_destination = null;
    }
    
    private bool on_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("on_drag_failed (%s): %d", page.get_page_name(), (int) drag_result);
        
        if (page == null)
            return false;
        
        drag_destination = null;
        
        return false;
    }
}

