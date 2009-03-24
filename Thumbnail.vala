
public class Thumbnail : Gtk.Alignment {
    public static const int LABEL_PADDING = 4;
    public static const int FRAME_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    public static const string SELECTED_COLOR = "#FF0";
    public static const string UNSELECTED_COLOR = "#FFF";
    
    public static const int MIN_SCALE = 64;
    public static const int MAX_SCALE = 360;
    public static const int DEFAULT_SCALE = 128;
    public static const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.HYPER;
    
    // Due to the potential for thousands or tens of thousands of thumbnails being present in a
    // particular view, all widgets used here should be NOWINDOW widgets.
    private PhotoID photoID;
    private File file;
    private int scale;
    private Gtk.Image image = new Gtk.Image();
    private Gtk.Label title = null;
    private Gtk.Frame frame = null;
    private bool selected = false;
    private bool isExposed = false;
    private Dimensions originalDim;
    private Dimensions scaledDim;
    private Gdk.Pixbuf cached = null;
    private Gdk.InterpType scaledInterp = LOW_QUALITY_INTERP;
    
    public Thumbnail(PhotoID photoID, File file, int scale = DEFAULT_SCALE) {
        this.photoID = photoID;
        this.file = file;
        this.scale = scale;
        this.originalDim = new PhotoTable().get_dimensions(photoID);
        this.scaledDim = get_scaled_dimensions(originalDim, scale);

        // bottom-align everything
        set(0, 1, 0, 0);
        
        // the image widget is only filled with a Pixbuf when exposed; if the pixbuf is cleared or
        // not present, the widget will collapse, and so the layout manager won't account for it
        // properly when it's off the viewport.  The solution is to manually set the widget's
        // requisition size, even when it contains no pixbuf
        image.requisition.width = scaledDim.width;
        image.requisition.height = scaledDim.height;
        
        title = new Gtk.Label(file.get_basename());
        title.set_use_underline(false);
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(TEXT_COLOR));
        
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.set_border_width(FRAME_PADDING);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);
        
        frame = new Gtk.Frame(null);
        frame.set_shadow_type(Gtk.ShadowType.ETCHED_OUT);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        frame.add(vbox);

        add(frame);
    }

    public static int get_max_width(int scale) {
        // TODO: Be more precise about this ... the magic 32 at the end is merely a dart on the board
        // for accounting for extra pixels used by the frame
        return scale + (FRAME_PADDING * 2) + 32;
    }

    public File get_file() {
        return file;
    }
    
    public PhotoID get_photo_id() {
        return photoID;
    }
    
    public Gtk.Allocation get_exposure() {
        return image.allocation;
    }

    public void select() {
        selected = true;

        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
    }

    public void unselect() {
        selected = false;

        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
    }

    public bool toggle_select() {
        if (selected) {
            unselect();
        } else {
            select();
        }
        
        return selected;
    }

    public bool is_selected() {
        return selected;
    }

    public void resize(int newScale) {
        assert((newScale >= MIN_SCALE) && (newScale <= MAX_SCALE));
        
        if (scale == newScale)
            return;

        int oldScale = scale;
        scale = newScale;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        
        if (isExposed) {
            if (ThumbnailCache.refresh_pixbuf(oldScale, newScale)) {
                cached = ThumbnailCache.fetch(photoID, newScale);
            }
            
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
            scaledInterp = LOW_QUALITY_INTERP;
            image.set_from_pixbuf(scaled);
        } else {
            image.requisition.width = scaledDim.width;
            image.requisition.height = scaledDim.height;
        }
    }
    
    public void paint_high_quality() {
        if (cached == null) {
            return;
        }
        
        if (scaledInterp == HIGH_QUALITY_INTERP) {
            return;
        }
        
        // only go through the scaling if indeed the image is going to be scaled ... although
        // scale_simple() will probably just return the pixbuf if it sees the stupid case, Gtk.Image
        // does not, and will fire off resized events when the new image (which is not really new)
        // is added
        if ((cached.get_width() != scaledDim.width) || (cached.get_height() != scaledDim.height)) {
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, HIGH_QUALITY_INTERP);
            image.set_from_pixbuf(scaled);
        }

        scaledInterp = HIGH_QUALITY_INTERP;
    }
    
    public void exposed() {
        if (isExposed)
            return;

        cached = ThumbnailCache.fetch(photoID, scale);
        Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
        scaledInterp = LOW_QUALITY_INTERP;
        image.set_from_pixbuf(scaled);
        isExposed = true;
    }
    
    public void unexposed() {
        if (!isExposed)
            return;

        cached = null;
        image.clear();
        image.requisition.width = scaledDim.width;
        image.requisition.height = scaledDim.height;
        isExposed = false;
    }
    
    public bool is_exposed() {
        return isExposed;
    }
}

