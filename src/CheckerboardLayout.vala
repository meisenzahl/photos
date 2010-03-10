/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

private class CheckerboardItemText {
    private static int one_line_height = 0;
    
    private string text;
    private bool marked_up;
    private Pango.Alignment alignment;
    private Pango.Layout layout = null;
    private bool single_line = true;
    private int height = 0;
    
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    public CheckerboardItemText(string text, Pango.Alignment alignment = Pango.Alignment.LEFT,
        bool marked_up = false) {
        this.text = text;
        this.marked_up = marked_up;
        this.alignment = alignment;
        
        single_line = is_single_line();
    }
    
    private bool is_single_line() {
        return text.chr(-1, '\n') == null;
    }
    
    public bool is_marked_up() {
        return marked_up;
    }
    
    public string get_text() {
        return text;
    }
    
    public int get_height() {
        if (height == 0)
            update_height();
        
        return height;
    }
    
    public Pango.Layout get_pango_layout(int max_width = 0) {
        if (layout == null)
            create_pango();
        
        if (max_width > 0)
            layout.set_width(max_width * Pango.SCALE);
        
        return layout;
    }
    
    private void update_height() {
        if (one_line_height != 0 && single_line)
            height = one_line_height;
        else
            create_pango();
    }
    
    private void create_pango() {
        // create layout for this string and ellipsize so it never extends past its laid-down width
        layout = AppWindow.get_instance().create_pango_layout(null);
        if (!marked_up)
            layout.set_text(text, -1);
        else
            layout.set_markup(text, -1);
        
        layout.set_ellipsize(Pango.EllipsizeMode.END);
        layout.set_alignment(alignment);
        
        // getting pixel size is expensive, and we only need the height, so use cached values
        // whenever possible
        if (one_line_height != 0 && single_line) {
            height = one_line_height;
        } else {
            int width;
            layout.get_pixel_size(out width, out height);
            
            // cache first one-line height discovered
            if (one_line_height == 0 && single_line)
                one_line_height = height;
        }
    }
}

public abstract class CheckerboardItem : ThumbnailView {
    // Collection properties CheckerboardItem understands
    // SHOW_TITLES (bool)
    public const string PROP_SHOW_TITLES = "show-titles";
    // SHOW_SUBTITLES (bool)
    public const string PROP_SHOW_SUBTITLES = "show-subtitles";
    
    public const int FRAME_WIDTH = 1;
    public const int LABEL_PADDING = 4;
    public const int FRAME_PADDING = 4;
    
    public const int TRINKET_SCALE = 12;
    public const int TRINKET_PADDING = 1;

    public const string SELECTED_COLOR = "#2DF";
    public const string UNSELECTED_COLOR = "#FFF";
    
    public const int BRIGHTEN_SHIFT = 0x18;
    
    public Dimensions requisition = Dimensions();
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    private bool exposure = false;
    private CheckerboardItemText? title = null;
    private bool title_visible = true;
    private CheckerboardItemText? subtitle = null;
    private bool subtitle_visible = false;
    private Gdk.Pixbuf pixbuf = null;
    private Gdk.Pixbuf display_pixbuf = null;
    private Gdk.Pixbuf brightened = null;
    private Dimensions pixbuf_dim = Dimensions();
    private int col = -1;
    private int row = -1;
    
    public CheckerboardItem(ThumbnailSource source, Dimensions initial_pixbuf_dim, string title,
        bool marked_up = false, Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base(source);
        
        pixbuf_dim = initial_pixbuf_dim;
        this.title = new CheckerboardItemText(title, alignment, marked_up);
        
        // Don't calculate size here, wait for the item to be assigned to a ViewCollection
        // (notify_membership_changed) and calculate when the collection's property settings
        // are known
    }
    
    public override string get_name() {
        return (title != null) ? title.get_text() : base.get_name();
    }
    
    public string get_title() {
        return (title != null) ? title.get_text() : "";
    }
    
    public void set_title(string text, bool marked_up = false,
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        title = new CheckerboardItemText(text, alignment, marked_up);
        
        if (title_visible) {
            recalc_size("set_title");
            notify_view_altered();
        }
    }
    
    public void clear_title() {
        title = null;
        
        if (title_visible) {
            recalc_size("clear_title");
            notify_view_altered();
        }
    }
    
    private void set_title_visible(bool visible) {
        if (title_visible == visible)
            return;
        
        title_visible = visible;
        
        recalc_size("set_title_visible");
        notify_view_altered();
    }
    
    public string get_subtitle() {
        return (subtitle != null) ? subtitle.get_text() : "";
    }
    
    public void set_subtitle(string text, bool marked_up = false, 
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        subtitle = new CheckerboardItemText(text, alignment, marked_up);
        
        if (subtitle_visible) {
            recalc_size("set_subtitle");
            notify_view_altered();
        }
    }
    
    public void clear_subtitle() {
        subtitle = null;
        
        if (subtitle_visible) {
            recalc_size("clear_subtitle");
            notify_view_altered();
        }
    }
    
    private void set_subtitle_visible(bool visible) {
        if (subtitle_visible == visible)
            return;
        
        subtitle_visible = visible;
        
        recalc_size("set_subtitle_visible");
        notify_view_altered();
    }
    
    protected override void notify_membership_changed(DataCollection? collection) {
        bool title_visible = (bool) get_collection_property(PROP_SHOW_TITLES, true);
        bool subtitle_visible = (bool) get_collection_property(PROP_SHOW_SUBTITLES, false);
        
        bool altered = false;
        if (this.title_visible != title_visible) {
            this.title_visible = title_visible;
            altered = true;
        }
        
        if (this.subtitle_visible != subtitle_visible) {
            this.subtitle_visible = subtitle_visible;
            altered = true;
        }
        
        if (altered || !requisition.has_area()) {
            recalc_size("notify_membership_changed");
            notify_view_altered();
        }
        
        base.notify_membership_changed(collection);
    }
    
    protected override void notify_collection_property_set(string name, Value? old, Value val) {
        switch (name) {
            case PROP_SHOW_TITLES:
                set_title_visible((bool) val);
            break;
            
            case PROP_SHOW_SUBTITLES:
                set_subtitle_visible((bool) val);
            break;
        }
        
        base.notify_collection_property_set(name, old, val);
    }
    
    // The alignment point is the coordinate on the y-axis (relative to the top of the
    // CheckerboardItem) which this item should be aligned to.  This allows for
    // bottom-alignment along the bottom edge of the thumbnail.
    public int get_alignment_point() {
        return FRAME_WIDTH + FRAME_PADDING + pixbuf_dim.height;
    }
    
    public virtual void exposed() {
        exposure = true;
    }
    
    public virtual void unexposed() {
        exposure = false;
    }
    
    public virtual bool is_exposed() {
        return exposure;
    }

    public bool has_image() {
        return pixbuf != null;
    }
    
    public Gdk.Pixbuf? get_image() {
        return pixbuf;
    }
    
    public void set_image(Gdk.Pixbuf pixbuf) {
        bool image_changed = pixbuf != this.pixbuf;
        
        this.pixbuf = pixbuf;
        display_pixbuf = pixbuf;
        pixbuf_dim = Dimensions.for_pixbuf(pixbuf);

        recalc_size("set_image");
        
        if (image_changed)
            notify_view_altered();
    }
    
    public void clear_image(Dimensions dim) {
        bool had_image = pixbuf != null;
        
        pixbuf = null;
        display_pixbuf = null;
        pixbuf_dim = dim;
        
        recalc_size("clear_image");
        
        if (had_image)
            notify_view_altered();
    }
    
    public static int get_max_width(int scale) {
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf (text
        // never wider)
        return (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + scale;
    }
    
    public virtual Gee.List<Gdk.Pixbuf>? get_trinkets(int scale) {
        return null;
    }
    
    private void recalc_size(string reason) {
        Dimensions old_requisition = requisition;
        
        // only add in the text heights if they're displayed
        int title_height = (title != null && title_visible)
            ? title.get_height() + LABEL_PADDING : 0;
        int subtitle_height = (subtitle != null && subtitle_visible)
            ? subtitle.get_height() + LABEL_PADDING : 0;
        
        // calculate width of all trinkets ... this is important because the trinkets could be
        // wider than the image, in which case need to expand for them
        int trinkets_width = 0;
        Gee.List<Gdk.Pixbuf>? trinkets = get_trinkets(TRINKET_SCALE);
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets)
                trinkets_width += trinket.get_width() + TRINKET_PADDING;
        }
        
        int image_width = int.max(trinkets_width, pixbuf_dim.width);
        
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf/trinkets
        // (text never wider)
        requisition.width = (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + image_width;
        
        // height is frame width (two sides) + frame padding (two sides) + height of pixbuf
        // + height of text + label padding (between pixbuf and text)
        requisition.height = (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + pixbuf_dim.height + title_height
            + subtitle_height;
        
#if TRACE_REFLOW_ITEMS
        debug("recalc_size %s: %s title_height=%d subtitle_height=%d requisition=%s", 
            get_source().get_name(), reason, title_height, subtitle_height, requisition.to_string());
#endif
        
        if (!requisition.approx_equals(old_requisition)) {
#if TRACE_REFLOW_ITEMS
            debug("recalc_size %s: %s notifying geometry altered", get_source().get_name(), reason);
#endif
            notify_geometry_altered();
        }
    }
    
    protected virtual void paint_image(Gdk.GC gc, Gdk.Drawable drawable, Gdk.Pixbuf pixbuf, Gdk.Point origin) {
        drawable.draw_pixbuf(gc, display_pixbuf, 0, 0, origin.x, origin.y, -1, -1, 
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    public void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        // frame of FRAME_WIDTH size (determined by GC) only if selected ... however, this is
        // accounted for in allocation so the frame can appear without resizing the item
        if (is_selected())
            drawable.draw_rectangle(gc, false, allocation.x, allocation.y, allocation.width - 1,
                pixbuf_dim.height + (FRAME_PADDING * 2) + FRAME_WIDTH);
        
        // calc the top-left point of the pixbuf
        Gdk.Point pixbuf_origin = Gdk.Point();
        pixbuf_origin.x = allocation.x + FRAME_WIDTH + FRAME_PADDING;
        pixbuf_origin.y = allocation.y + FRAME_WIDTH + FRAME_PADDING;
        
        if (display_pixbuf != null)
            paint_image(gc, drawable, display_pixbuf, pixbuf_origin);
        
        // get trinkets to determine the max width (pixbuf vs. trinkets)
        int trinkets_width = 0;
        Gee.List<Gdk.Pixbuf>? trinkets = get_trinkets(TRINKET_SCALE);
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets)
                trinkets_width += trinket.get_width();
        }
        
        int image_width = int.max(trinkets_width, pixbuf_dim.width);
        
        // title and subtitles are LABEL_PADDING below bottom of pixbuf
        int text_y = allocation.y + FRAME_WIDTH + FRAME_PADDING + pixbuf_dim.height + FRAME_PADDING
            + FRAME_WIDTH + LABEL_PADDING;
        if (title != null && title_visible) {
            // get the layout sized so its with is no more than the pixbuf's
            // resize the text width to be no more than the pixbuf's
            title.allocation = { allocation.x + FRAME_WIDTH + FRAME_PADDING, text_y,
                image_width, title.get_height() };
            
            Gdk.draw_layout(drawable, gc, title.allocation.x, title.allocation.y,
                title.get_pango_layout(image_width));
            
            text_y += title.get_height() + LABEL_PADDING;
        }
        
        if (subtitle != null && subtitle_visible) {
            subtitle.allocation = { allocation.x + FRAME_WIDTH + FRAME_PADDING, text_y,
                image_width, subtitle.get_height() };
            
            Gdk.draw_layout(drawable, gc, subtitle.allocation.x, subtitle.allocation.y,
                subtitle.get_pango_layout(image_width));
            
            // increment text_y if more text lines follow
        }
        
        // draw trinkets last
        if (trinkets != null) {
            int current_trinkets_width = 0;
            foreach (Gdk.Pixbuf trinket in trinkets) {
                current_trinkets_width = current_trinkets_width + trinket.get_width() + TRINKET_PADDING;
                drawable.draw_pixbuf(gc, trinket, 0, 0, 
                    pixbuf_origin.x + pixbuf_dim.width - current_trinkets_width,
                    pixbuf_origin.y + pixbuf_dim.height - trinket.get_height() - TRINKET_PADDING, 
                    trinket.get_width(), trinket.get_height(), Gdk.RgbDither.NORMAL, 0, 0);
            }
        }
    }

    public void set_grid_coordinates(int col, int row) {
        this.col = col;
        this.row = row;
    }
    
    public int get_column() {
        return col;
    }
    
    public int get_row() {
        return row;
    }
    
    public void brighten() {
        // "should" implies "can" and "didn't already"
        if (brightened != null || pixbuf == null)
            return;
        
        // create a new lightened pixbuf to display
        brightened = pixbuf.copy();
        shift_colors(brightened, BRIGHTEN_SHIFT, BRIGHTEN_SHIFT, BRIGHTEN_SHIFT, 0);
        
        display_pixbuf = brightened;
        
        notify_view_altered();
    }
    
    public void unbrighten() {
        // "should", "can", "didn't already"
        if (brightened == null || pixbuf == null)
            return;
        
        brightened = null;

        // return to the normal image
        display_pixbuf = pixbuf;
        
        notify_view_altered();
    }
    
    public override void visibility_changed(bool visible) {
         // if going from visible to hidden, unbrighten
         if (!visible)
            unbrighten();
    }
    
    private bool query_tooltip_on_text(CheckerboardItemText text, Gtk.Tooltip tooltip) {
        if (!text.get_pango_layout().is_ellipsized())
            return false;
        
        if (text.is_marked_up())
            tooltip.set_markup(text.get_text());
        else
            tooltip.set_text(text.get_text());
        
        return true;
    }
    
    public bool query_tooltip(int x, int y, Gtk.Tooltip tooltip) {
        if (title != null && title_visible && coord_in_rectangle(x, y, title.allocation))
            return query_tooltip_on_text(title, tooltip);
        
        if (subtitle != null && subtitle_visible && coord_in_rectangle(x, y, subtitle.allocation))
            return query_tooltip_on_text(subtitle, tooltip);
        
        return false;
    }
}

public class CheckerboardLayout : Gtk.DrawingArea {
    public const int TOP_PADDING = 16;
    public const int BOTTOM_PADDING = 16;
    public const int ROW_GUTTER_PADDING = 24;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public const int COLUMN_GUTTER_PADDING = 24;
    
    private class LayoutRow {
        public int y;
        public int height;
        public CheckerboardItem[] items;
        
        public LayoutRow(int y, int height, int num_in_row) {
            this.y = y;
            this.height = height;
            this.items = new CheckerboardItem[num_in_row];
        }
    }
    
    private static Gdk.Pixbuf selection_interior = null;

    private ViewCollection view;
    private string page_name = "";
    private LayoutRow[] item_rows = null;
    private Gee.HashSet<CheckerboardItem> exposed_items = new Gee.HashSet<CheckerboardItem>();
    private Gtk.Adjustment hadjustment = null;
    private Gtk.Adjustment vadjustment = null;
    private string message = null;
    private Gdk.GC selected_gc = null;
    private Gdk.GC unselected_gc = null;
    private Gdk.GC selection_band_gc = null;
    private bool in_view = false;
    private Gdk.Rectangle visible_page = Gdk.Rectangle();
    private int last_width = 0;
    private int columns = 0;
    private int rows = 0;
    private Gdk.Point drag_origin = Gdk.Point();
    private Gdk.Point drag_endpoint = Gdk.Point();
    private Gdk.Rectangle selection_band = Gdk.Rectangle();
    private uint32 selection_transparency_color = 0;
    private OneShotScheduler reflow_scheduler = null;
    private int scale = 0;
    private bool flow_dirty = true;

    public CheckerboardLayout(ViewCollection view) {
        this.view = view;
        
        clear_drag_select();
        
        reflow_scheduler = new OneShotScheduler("CheckerboardLayout for %s".printf(view.to_string()),
            background_reflow);
        
        // subscribe to the new collection
        view.contents_altered += on_contents_altered;
        view.items_altered += on_items_altered;
        view.items_metadata_altered += on_items_metadata_altered;
        view.items_state_changed += on_items_state_changed;
        view.items_visibility_changed += on_items_visibility_changed;
        view.ordering_changed += on_ordering_changed;
        view.views_altered += on_views_altered;
        view.geometries_altered += on_geometries_altered;
        
        modify_bg(Gtk.StateType.NORMAL, AppWindow.BG_COLOR);
        
        // CheckerboardItems offer tooltips
        has_tooltip = true;
    }
    
    ~CheckerboardLayout() {
#if TRACE_DTORS
        debug("DTOR: CheckerboardLayout for %s", view.to_string());
#endif

        view.contents_altered -= on_contents_altered;
        view.items_altered -= on_items_altered;
        view.items_metadata_altered -= on_items_metadata_altered;
        view.items_state_changed -= on_items_state_changed;
        view.items_visibility_changed -= on_items_visibility_changed;
        view.ordering_changed -= on_ordering_changed;
        view.views_altered -= on_views_altered;
        view.geometries_altered -= on_geometries_altered;
        
        if (hadjustment != null)
            hadjustment.value_changed -= on_viewport_shifted;
        
        if (vadjustment != null)
            vadjustment.value_changed -= on_viewport_shifted;
        
        if (parent != null)
            parent.size_allocate -= on_viewport_resized;
        
        reflow_scheduler.cancel();
    }
    
    public void set_adjustments(Gtk.Adjustment hadjustment, Gtk.Adjustment vadjustment) {
        this.hadjustment = hadjustment;
        this.vadjustment = vadjustment;
        
        // monitor adjustment changes to report when the visible page shifts
        hadjustment.value_changed += on_viewport_shifted;
        vadjustment.value_changed += on_viewport_shifted;
        
        // monitor parent's size changes for a similar reason
        parent.size_allocate += on_viewport_resized;
    }
    
    // This method allows for some optimizations to occur in reflow() by using the known max.
    // width of all items in the layout.
    public void set_scale(int scale) {
        this.scale = scale;
    }
    
    public int get_scale() {
        return scale;
    }
    
    public void set_name(string name) {
        page_name = name;
    }
    
    private void on_viewport_resized() {
        Gtk.Requisition req;
        size_request(out req);

        if (message == null) {
            // set the layout's new size to be the same as the parent's width but maintain 
            // it's own height
            set_size_request(parent.allocation.width, req.height);
        } else {
            // set the layout's width and height to always match the parent's
            set_size_request(parent.allocation.width, parent.allocation.height);
        }
        
        // possible for this widget's size_allocate not to be called, so need to update the page
        // rect here
        update_visible_page();
    }
    
    private void on_viewport_shifted() {
        update_visible_page();
    }
    
    private void on_contents_altered(Gee.Iterable<DataObject>? added, 
        Gee.Iterable<DataObject>? removed) {
        if (added != null)
            message = null;
        
        if (removed != null) {
            foreach (DataObject object in removed)
                exposed_items.remove((CheckerboardItem) object);
        }
        
        // release spatial data structure ... contents_altered means a reflow is required, and since
        // items may be removed, this ensures we're not holding the ref on a removed view
        item_rows = null;
        
        schedule_background_reflow("on_contents_altered");
    }
    
    private void on_items_altered() {
        schedule_background_reflow("on_items_altered");
    }
    
    private void on_items_metadata_altered() {
        schedule_background_reflow("on_items_metadata_altered");
    }
    
    private void on_items_state_changed(Gee.Iterable<DataView> changed) {
        if (in_view)
            repaint_items("on_items_state_changed", changed);
    }
    
    private void on_items_visibility_changed(Gee.Iterable<DataView> changed) {
        schedule_background_reflow("on_items_visibility_changed");
    }
    
    private void on_ordering_changed() {
        schedule_background_reflow("on_ordering_changed");
    }
    
    private void on_views_altered(Gee.Collection<DataView> altered) {
        if (in_view)
            repaint_items("on_views_altered", altered);
    }
    
    private void on_geometries_altered() {
        schedule_background_reflow("on_geometries_altered");
    }
    
    private void schedule_background_reflow(string caller) {
#if TRACE_REFLOW
        debug("schedule_background_reflow %s: %s (in_view=%d)", page_name, caller, (int) in_view);
#endif
        
        if (in_view)
            reflow_scheduler.at_priority_idle(Priority.HIGH);
        else
            flow_dirty = true;
    }
    
    private void background_reflow() {
        reflow("background_reflow");
    }
    
    public void set_message(string text) {
        message = text;

        // set the layout's size to be exactly the same as the parent's
        if (parent != null)
            set_size_request(parent.allocation.width, parent.allocation.height);
    }
    
    private void update_visible_page(bool reexpose = true) {
        if (hadjustment == null || vadjustment == null)
            return;
            
        Gdk.Rectangle current_visible = get_adjustment_page(hadjustment, vadjustment);
        
        bool changed = !rectangles_equal(visible_page, current_visible);
        
        visible_page = current_visible;
        
        if (!reexpose || !in_view || !changed)
            return;
        
        // create a new hash set of exposed items that represents an intersection of the old set
        // and the new
        Gee.HashSet<CheckerboardItem> new_exposed_items = new Gee.HashSet<CheckerboardItem>();
        
        view.freeze_notifications();
        
        Gee.List<CheckerboardItem> items = intersection(visible_page);
        foreach (CheckerboardItem item in items) {
            new_exposed_items.add(item);

            // if not in the old list, then need to expose
            if (!exposed_items.remove(item))
                item.exposed();
        }
        
        // everything remaining in the old exposed list is now unexposed
        foreach (CheckerboardItem item in exposed_items)
            item.unexposed();
        
        // swap out lists
        exposed_items = new_exposed_items;
        
        view.thaw_notifications();
    }
    
    public void set_in_view(bool in_view) {
        this.in_view = in_view;
        if (in_view) {
            // update the visible page rectangle, but only re-expose items if not going to reflow
            // the layout (which exposes already)
            update_visible_page(!flow_dirty);
            
            // if the flow dirtied at some point, now reflow the layout
            if (flow_dirty)
                reflow("set_in_view");

            return;
        }
        
        // clear this to force a re-expose when back in view
        visible_page = Gdk.Rectangle();

        // unexpose everything currently exposed
        view.freeze_notifications();
        foreach (CheckerboardItem item in exposed_items)
            item.unexposed();
        
        exposed_items.clear();
        view.thaw_notifications();
    }
    
    public CheckerboardItem? get_item_at_pixel(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;
        
        // look for the row in the range of the pixel
        LayoutRow in_range = null;
        foreach (LayoutRow row in item_rows) {
            // this happens when there is an exact number of elements to fill the last row
            if (row == null)
                continue;
            
            if (y < row.y) {
                // overshot ... this happens because there's gaps in the rows
                break;
            }

            // if inside height range, this is it
            if (y <= (row.y + row.height)) {
                in_range = row;
                
                break;
            }
        }
        
        if (in_range == null)
            return null;
        
        // look for item in row's column in range of the pixel
        foreach (CheckerboardItem item in in_range.items) {
            // this happens on an incompletely filled-in row (usually the last one with empty
            // space remaining)
            if (item == null)
                continue;
            
            if (x < item.allocation.x) {
                // overshot ... this happens because there's gaps in the columns
                break;
            }
            
            // need to verify actually over item's full dimensions, since they vary in size inside 
            // a row
            if (x <= (item.allocation.x + item.allocation.width) && y >= item.allocation.y 
                && y <= (item.allocation.y + item.allocation.height))
                return item;
        }

        return null;
    }
    
    public Gee.List<CheckerboardItem> get_visible_items() {
        return intersection(visible_page);
    }
    
    public Gee.List<CheckerboardItem> intersection(Gdk.Rectangle area) {
        Gee.ArrayList<CheckerboardItem> intersects = new Gee.ArrayList<CheckerboardItem>();
        
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        foreach (LayoutRow row in item_rows) {
            if (row == null)
                continue;
            
            if ((area.y + area.height) < row.y) {
                // overshoot
                break;
            }
            
            if ((row.y + row.height) < area.y) {
                // haven't reached it yet
                continue;
            }
            
            // see if the row intersects the area
            Gdk.Rectangle row_rect = Gdk.Rectangle();
            row_rect.x = 0;
            row_rect.y = row.y;
            row_rect.width = allocation.width;
            row_rect.height = row.height;
            
            if (area.intersect(row_rect, bitbucket)) {
                // see what elements, if any, intersect the area
                foreach (CheckerboardItem item in row.items) {
                    if (item == null)
                        continue;
                    
                    if (area.intersect(item.allocation, bitbucket))
                        intersects.add(item);
                }
            }
        }

        return intersects;
    }
    
    public CheckerboardItem? get_item_relative_to(CheckerboardItem item, CompassPoint point) {
        if (view.get_count() == 0)
            return null;
        
        assert(columns > 0);
        assert(rows > 0);
        
        int col = item.get_column();
        int row = item.get_row();
        
        if (col < 0 || row < 0) {
            critical("Attempting to locate item not placed in layout: %s", item.get_title());
            
            return null;
        }
        
        switch (point) {
            case CompassPoint.NORTH:
                if (--row < 0)
                    row = 0;
            break;
            
            case CompassPoint.SOUTH:
                if (++row >= rows)
                    row = rows - 1;
            break;
            
            case CompassPoint.EAST:
                if (++col >= columns) {
                    if(++row >= rows) {
                        row = rows - 1;
                        col = columns - 1;
                    } else {
                        col = 0;
                    }
                }
            break;
            
            case CompassPoint.WEST:
                if (--col < 0) {
                    if (--row < 0) {
                        row = 0;
                        col = 0;
                    } else {
                        col = columns - 1;
                    }
                }
            break;
            
            default:
                error("Bad compass point %d", (int) point);
            break;
        }
        
        CheckerboardItem new_item = get_item_at_coordinate(col, row);
        
        return (new_item != null) ? new_item : item;
    }
    
    public CheckerboardItem? get_item_at_coordinate(int col, int row) {
        if (row >= item_rows.length)
            return null;
            
        LayoutRow item_row = item_rows[row];
        if (item_row == null)
            return null;
        
        if (col >= item_row.items.length)
            return null;
        
        return item_row.items[col];
    }
    
    public void set_drag_select_origin(int x, int y) {
        clear_drag_select();
        
        drag_origin.x = x.clamp(0, allocation.width);
        drag_origin.y = y.clamp(0, allocation.height);
    }
    
    public void set_drag_select_endpoint(int x, int y) {
        drag_endpoint.x = x.clamp(0, allocation.width);
        drag_endpoint.y = y.clamp(0, allocation.height);
        
        // drag_origin and drag_endpoint are maintained only to generate selection_band; all reporting
        // and drawing functions refer to it, not drag_origin and drag_endpoint
        Gdk.Rectangle old_selection_band = selection_band;
        selection_band = Box.from_points(drag_origin, drag_endpoint).get_rectangle();
        
        // force repaint of the union of the old and new, which covers the band reducing in size
        if (window != null) {
            Gdk.Rectangle union;
            selection_band.union(old_selection_band, out union);
            
            queue_draw_area(union.x, union.y, union.width, union.height);
        }
    }
    
    public Gee.List<CheckerboardItem>? items_in_selection_band() {
        if (!Dimensions.for_rectangle(selection_band).has_area())
            return null;

        return intersection(selection_band);
    }
    
    public bool is_drag_select_active() {
        return drag_origin.x >= 0 && drag_origin.y >= 0;
    }
    
    public void clear_drag_select() {
        selection_band = Gdk.Rectangle();
        drag_origin.x = -1;
        drag_origin.y = -1;
        drag_endpoint.x = -1;
        drag_endpoint.y = -1;
        
        // force a total repaint to clear the selection band
        queue_draw();
    }
    
    private void reflow(string caller) {
        // if set in message mode, nothing to do here
        if (message != null)
            return;
        
        // don't bother until layout is of some appreciable size (even this is too low)
        if (allocation.width <= 1)
            return;
        
        // don't reflow if not in view of the user
        if (!in_view) {
            flow_dirty = true;
            
            return;
        }
        
        int total_items = view.get_count();
        
        // clear the rows data structure, as the reflow will completely rearrange it
        item_rows = null;
        
        // need to set_size in case all items were removed and the viewport size has changed
        if (total_items == 0) {
            set_size_request(allocation.width, 0);
            item_rows = new LayoutRow[0];
            flow_dirty = false;

            return;
        }
        
#if TRACE_REFLOW
        debug("reflow %s: %s (%d items)", page_name, caller, total_items);
#endif
        
        // Step 1: Determine the widest row in the layout, and from it the number of columns.
        // If owner supplies an image scaling for all items in the layout, then this can be
        // calculated quickly.
        int max_cols = 0;
        if (scale > 0) {
            // calculate interior width
            int remaining_width = allocation.width - (COLUMN_GUTTER_PADDING * 2);
            int max_item_width = CheckerboardItem.get_max_width(scale);
            max_cols = remaining_width / max_item_width;
            if (max_cols <= 0)
                max_cols = 1;
            
            // if too large with gutters, decrease until columns fit
            while (max_cols > 1 
                && ((max_cols * max_item_width) + ((max_cols - 1) * COLUMN_GUTTER_PADDING) > remaining_width)) {
#if TRACE_REFLOW
                debug("reflow %s: scaled cols estimate: reducing max_cols from %d to %d", page_name,
                    max_cols, max_cols - 1);
#endif
                max_cols--;
            }
            
            // special case: if fewer items than columns, they are the columns
            if (total_items < max_cols)
                max_cols = total_items;
            
#if TRACE_REFLOW
            debug("reflow %s: scaled cols estimate: max_cols=%d remaining_width=%d max_item_width=%d",
                page_name, max_cols, remaining_width, max_item_width);
#endif
        } else {
            int x = COLUMN_GUTTER_PADDING;
            int col = 0;
            int row_width = 0;
            int widest_row = 0;

            for (int ctr = 0; ctr < total_items; ctr++) {
                CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
                Dimensions req = item.requisition;
                
                // the items must be requisitioned for this code to work
                assert(req.has_area());
                
                // carriage return (i.e. this item will overflow the view)
                if ((x + req.width + COLUMN_GUTTER_PADDING) > allocation.width) {
                    if (row_width > widest_row) {
                        widest_row = row_width;
                        max_cols = col;
                    }
                    
                    col = 0;
                    x = COLUMN_GUTTER_PADDING;
                    row_width = 0;
                }
                
                x += req.width + COLUMN_GUTTER_PADDING;
                row_width += req.width;
                
                col++;
            }
            
            // account for dangling last row
            if (row_width > widest_row)
                max_cols = col;
            
#if TRACE_REFLOW
            debug("reflow %s: manual cols estimate: max_cols=%d widest_row=%d", page_name, max_cols,
                widest_row);
#endif
        }
        
        assert(max_cols > 0);
        int max_rows = (total_items / max_cols) + 1;
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int widest = 0;
        int row_alignment_point = 0;
        int total_width = 0;
        int col = 0;
        int[] column_widths = new int[max_cols];
        int[] row_heights = new int[max_rows];
        int[] alignment_points = new int[max_rows];
        int gutter = 0;
        
        for (;;) {
            for (int ctr = 0; ctr < total_items; ctr++ ) {
                CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
                Dimensions req = item.requisition;
                int alignment_point = item.get_alignment_point();
                
                // alignment point better be sane
                assert(alignment_point < req.height);
                
                if (req.height > tallest)
                    tallest = req.height;
                
                if (req.width > widest)
                    widest = req.width;
                
                if (alignment_point > row_alignment_point)
                    row_alignment_point = alignment_point;
                
                // store largest thumb size of each column as well as track the total width of the
                // layout (which is the sum of the width of each column)
                if (column_widths[col] < req.width) {
                    total_width -= column_widths[col];
                    column_widths[col] = req.width;
                    total_width += req.width;
                }

                if (++col >= max_cols) {
                    alignment_points[row] = row_alignment_point;
                    row_heights[row++] = tallest;
                    
                    col = 0;
                    row_alignment_point = 0;
                    tallest = 0;
                }
            }
            
            // account for final dangling row
            if (col != 0) {
                alignment_points[row] = row_alignment_point;
                row_heights[row] = tallest;
            }
            
            // Step 3: Calculate the gutter between the items as being equidistant of the
            // remaining space (adding one gutter to account for the right-hand one)
            gutter = (allocation.width - total_width) / (max_cols + 1);
            
            // if only one column, gutter size could be less than minimums
            if (max_cols == 1)
                break;

            // have to reassemble if the gutter is too small ... this happens because Step One
            // takes a guess at the best column count, but when the max. widths of the columns are
            // added up, they could overflow
            if (gutter < COLUMN_GUTTER_PADDING) {
                max_cols--;
                max_rows = (total_items / max_cols) + 1;
                
#if TRACE_REFLOW
                debug("reflow %s: readjusting columns: alloc.width=%d total_width=%d widest=%d gutter=%d max_cols now=%d", 
                    page_name, allocation.width, total_width, widest, gutter, max_cols);
#endif
                
                col = 0;
                row = 0;
                tallest = 0;
                widest = 0;
                total_width = 0;
                column_widths = new int[max_cols];
                row_heights = new int[max_rows];
                alignment_points = new int[max_rows];
            } else {
                break;
            }
        }

#if TRACE_REFLOW
        debug("reflow %s: width:%d total_width:%d max_cols:%d gutter:%d", page_name, allocation.width, 
            total_width, max_cols, gutter);
#endif
        
        // Step 4: Recalculate the height of each row according to the row's alignment point (which
        // may cause shorter items to extend below the bottom of the tallest one, extending the
        // height of the row)
        col = 0;
        row = 0;
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
            Dimensions req = item.requisition;
            
            // this determines how much padding the item requires to be bottom-alignment along the
            // alignment point; add to the height and you have the item's "true" height on the 
            // laid-down row
            int true_height = req.height + (alignment_points[row] - item.get_alignment_point());
            assert(true_height >= req.height);
            
            // add that to its height to determine it's actual height on the laid-down row
            if (true_height > row_heights[row]) {
#if TRACE_REFLOW
                debug("reflow %s: Adjusting height of row %d from %d to %d", page_name, row,
                    row_heights[row], true_height);
#endif
                row_heights[row] = true_height;
            }
            
            // carriage return
            if (++col >= max_cols) {
                col = 0;
                row++;
            }
        }
        
        // for the spatial structure
        item_rows = new LayoutRow[max_rows];
        
        // Step 5: Lay out the items in the space using all the information gathered
        int x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;
        LayoutRow current_row = null;
        bool report_exposure = (visible_page.width > 1 && visible_page.height > 1);
        Gdk.Rectangle intersection = Gdk.Rectangle();
        Gdk.Point tl_dirty = { int.MAX, int.MAX };
        Gdk.Point br_dirty = { int.MIN, int.MIN };
        bool dirty_area = false;
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
            Dimensions req = item.requisition;
            
            // this centers the item in the column
            int xpadding = (column_widths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the item along the discovered alignment point
            int ypadding = alignment_points[row] - item.get_alignment_point();
            assert(ypadding >= 0);
            
            // save pixel and grid coordinates
            Gdk.Rectangle allocation = { x + xpadding, y + ypadding, req.width, req.height };
            if (!rectangles_equal(allocation, item.allocation)) {
                // if the item has already been allocated, find the maximum area of the change
                // between the current changed rectangle, the old allocation, and the new allocation
                if (item.allocation.width > 0 && item.allocation.height > 0) {
                    tl_dirty.x = int.min(tl_dirty.x, int.min(allocation.x, item.allocation.x));
                    tl_dirty.y = int.min(tl_dirty.y, int.min(allocation.y, item.allocation.y));
                    br_dirty.x = int.max(br_dirty.x,
                        int.max(allocation.x + allocation.width, item.allocation.x + item.allocation.width));
                    br_dirty.y = int.max(br_dirty.y,
                        int.max(allocation.y + allocation.height, item.allocation.y + item.allocation.height));
                } else {
                    // since the item has not been allocated, only need to find the maximum area
                    // of the old dirty area and the new allocation
                    tl_dirty.x = int.min(tl_dirty.x, allocation.x);
                    tl_dirty.y = int.min(tl_dirty.y, allocation.y);
                    br_dirty.x = int.max(br_dirty.x, allocation.x + allocation.width);
                    br_dirty.y = int.max(br_dirty.y, allocation.y + allocation.height);
                }
                
                dirty_area = true;
                
                item.allocation = allocation;
            }
            item.set_grid_coordinates(col, row);
            
            // report exposed or unexposed
            if (report_exposure) {
                if (item.allocation.intersect(visible_page, intersection)) {
                    exposed_items.add(item);
                    item.exposed();
                } else {
                    exposed_items.remove(item);
                    item.unexposed();
                }
            }
            
            // add to current row in spatial data structure
            if (current_row == null)
                current_row = new LayoutRow(y, row_heights[row], max_cols);
            
            current_row.items[col] = item;

            x += column_widths[col] + gutter;

            // carriage return
            if (++col >= max_cols) {
                assert(current_row != null);
                item_rows[row] = current_row;
                current_row = null;

                x = gutter;
                y += row_heights[row] + ROW_GUTTER_PADDING;
                col = 0;
                row++;
            }
        }
        
        // add last row to spatial data structure
        if (current_row != null)
            item_rows[row] = current_row;
        
        // save dimensions of checkerboard
        columns = max_cols;
        rows = row + 1;
        assert(rows == max_rows);
        
        // Step 6: Define the total size of the page as the size of the allocated width and
        // the height of all the items plus padding
        int total_height = y + row_heights[row] + BOTTOM_PADDING;
        if (total_height != allocation.height) {
#if TRACE_REFLOW
            debug("reflow %s: Changing layout dimensions from %dx%d to %dx%d", page_name, 
                allocation.width, allocation.height, allocation.width, total_height);
#endif
            set_size_request(allocation.width, total_height);
        }
        
        flow_dirty = false;
        
        // Step 7: Queue redraw of dirty area, if any
        if (dirty_area) {
            Gdk.Rectangle dirty = { tl_dirty.x, tl_dirty.y, br_dirty.x - tl_dirty.x,
                br_dirty.y - tl_dirty.y };
            
            // Verify the rectangle has area and find the intersection between it and the visible
            // page; if there's an intersection, queue it for redraw
            if (dirty.width > 0 && dirty.height > 0 && dirty.intersect(visible_page, intersection)) {
#if TRACE_REFLOW
                debug("reflow %s: Queueing redraw on %s of visible page %s", page_name, 
                    rectangle_to_string(intersection), rectangle_to_string(visible_page));
#endif
                queue_draw_area(intersection.x, intersection.y, intersection.width, intersection.height);
            }
        }
    }
    
    private void repaint_items(string reason, Gee.Iterable<DataView> items) {
        Gdk.Rectangle dirty = Gdk.Rectangle();
        foreach (DataView data_view in items) {
            CheckerboardItem item = (CheckerboardItem) data_view;
            
            if (!item.is_visible())
                continue;
            
            assert(view.contains(item));
            
            // if not allocated, need to reflow the entire layout; don't bother queueing a draw
            // for any of these, reflow will handle that
            if (item.allocation.width <= 0 || item.allocation.height <= 0) {
                schedule_background_reflow("repaint_item: %s".printf(reason));
                
                return;
            }
            
            // only mark area as dirty if visible in viewport
            Gdk.Rectangle intersection = Gdk.Rectangle();
            if (!visible_page.intersect(item.allocation, intersection))
                continue;
            
            // grow the dirty area
            if (dirty.width == 0 || dirty.height == 0)
                dirty = intersection;
            else
                dirty.union(intersection, out dirty);
        }
        
        if (dirty.width > 0 && dirty.height > 0) {
#if TRACE_REFLOW
            debug("repaint_items %s (%s): Queuing draw of dirty area %s on visible_page %s",
                page_name, reason, rectangle_to_string(dirty), rectangle_to_string(visible_page));
#endif
            queue_draw_area(dirty.x, dirty.y, dirty.width, dirty.height);
        }
    }
    
    private override void map() {
        base.map();
        
        // set up selected/unselected colors
        Gdk.Color selected_color = fetch_color(CheckerboardItem.SELECTED_COLOR, window);
        Gdk.Color unselected_color = fetch_color(CheckerboardItem.UNSELECTED_COLOR, window);
        selection_transparency_color = convert_rgba(selected_color, 0x40);

        // set up GC's for painting layout items
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.foreground = selected_color;
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_width = CheckerboardItem.FRAME_WIDTH;
        
        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND 
            | Gdk.GCValuesMask.FUNCTION 
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH;

        selected_gc = new Gdk.GC.with_values(window, gc_values, mask);
        
        gc_values.foreground = unselected_color;
        
        unselected_gc = new Gdk.GC.with_values(window, gc_values, mask);

        gc_values.line_width = 1;
        gc_values.foreground = selected_color;
        
        selection_band_gc = new Gdk.GC.with_values(window, gc_values, mask);
    }
    
    private override void size_allocate(Gdk.Rectangle allocation) {
        base.size_allocate(allocation);
        
        // only reflow() if the width has changed
        if (allocation.width != last_width) {
            last_width = allocation.width;
            
            // update visible page rect but don't call expose events, as reflow will do that
            update_visible_page(false);
            
            schedule_background_reflow("size_allocate (%d)".printf(last_width));
        } else {
            // update visible page rect, re-exposing as necessary
            update_visible_page();
        }
    }
    
    private override bool expose_event(Gdk.EventExpose event) {
        // Note: It's possible for expose_event to be called when in_view is false; this happens
        // when pages are switched prior to switched_to() being called, and some of the other
        // controls allow for events to be processed while they are orienting themselves.  Since
        // we want switched_to() to be the final call in the process (indicating that the page is
        // now in place and should do its thing to update itself), have to be be prepared for
        // GTK/GDK calls between the widgets being actually present on the screen and "switched to"
        
        // watch for message mode
        if (message == null) {
#if TRACE_REFLOW
            debug("expose_event %s: %s", page_name, rectangle_to_string(event.area));
#endif
            // have all items in the exposed area paint themselves
            foreach (CheckerboardItem item in intersection(event.area))
                item.paint(item.is_selected() ? selected_gc : unselected_gc, window);
        } else {
            // draw the message in the center of the window
            Pango.Layout pango_layout = create_pango_layout(message);
            int text_width, text_height;
            pango_layout.get_pixel_size(out text_width, out text_height);
            
            int x = allocation.width - text_width;
            x = (x > 0) ? x / 2 : 0;
            
            int y = allocation.height - text_height;
            y = (y > 0) ? y / 2 : 0;

            Gdk.draw_layout(window, style.white_gc, x, y, pango_layout);
        }

        bool result = (base.expose_event != null) ? base.expose_event(event) : true;
        
        // draw the selection band last, so it appears floating over everything else
        draw_selection_band(event);

        return result;
    }
    
    private void draw_selection_band(Gdk.EventExpose event) {
        // no selection band, nothing to draw
        if (selection_band.width <= 1 || selection_band.height <= 1)
            return;
        
        // This requires adjustments
        if (hadjustment == null || vadjustment == null)
            return;
        
        // find the visible intersection of the viewport and the selection band
        Gdk.Rectangle visible_page = get_adjustment_page(hadjustment, vadjustment);
        Gdk.Rectangle visible_band = Gdk.Rectangle();
        visible_page.intersect(selection_band, visible_band);
        
        // pixelate selection rectangle interior
        if (visible_band.width > 1 && visible_band.height > 1) {
            // generate a pixbuf of the selection color with a transparency to paint over the
            // visible selection area ... reuse old pixbuf (which is shared among all instances)
            // if possible
            if (selection_interior == null || selection_interior.width < visible_band.width
                || selection_interior.height < visible_band.height) {
                selection_interior = new Gdk.Pixbuf(Gdk.Colorspace.RGB, true, 8, visible_band.width,
                    visible_band.height);
                selection_interior.fill(selection_transparency_color);
            }
            
            window.draw_pixbuf(selection_band_gc, selection_interior, 0, 0, visible_band.x, 
                visible_band.y, visible_band.width, visible_band.height, Gdk.RgbDither.NORMAL, 0, 0);
        }

        // border
        Gdk.draw_rectangle(window, selection_band_gc, false, selection_band.x, selection_band.y,
            selection_band.width - 1, selection_band.height - 1);
    }
    
    private override bool query_tooltip(int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
        CheckerboardItem? item = get_item_at_pixel(x, y);
        
        return (item != null) ? item.query_tooltip(x, y, tooltip) : false;
    }
}
