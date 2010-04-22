/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class PixbufCache : Object {
    public enum PhotoType {
        REGULAR,
        ORIGINAL
    }
    
    private abstract class FetchJob : BackgroundJob {
        public BackgroundJob.JobPriority priority;
        public TransformablePhoto photo;
        public Scaling scaling;
        public Gdk.Pixbuf pixbuf = null;
        public Error err = null;
        
        private Semaphore completion_semaphore = new Semaphore();
        
        public FetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, TransformablePhoto photo, 
            Scaling scaling, CompletionCallback callback) {
            base(owner, callback, new Cancellable());
            
            this.priority = priority;
            this.photo = photo;
            this.scaling = scaling;
            
            set_completion_semaphore(completion_semaphore);
        }
        
        public override BackgroundJob.JobPriority get_priority() {
            return priority;
        }
        
        public void wait_for_completion() {
            completion_semaphore.wait();
        }
    }
    
    private class RegularFetchJob : FetchJob {
        public RegularFetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, TransformablePhoto photo, 
            Scaling scaling, CompletionCallback callback) {
            base(owner, priority, photo, scaling, callback);
        }
        
        public override void execute() {
            try {
                pixbuf = photo.get_pixbuf(scaling);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class OriginalFetchJob : FetchJob {
        public OriginalFetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, TransformablePhoto photo, 
            Scaling scaling, CompletionCallback callback) {
            base(owner, priority, photo, scaling, callback);
        }
        
        public override void execute() {
            try {
                pixbuf = photo.get_original_pixbuf(scaling);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private static Workers background_workers = null;
    
    private SourceCollection sources;
    private PhotoType type;
    private int max_count;
    private Scaling scaling;
    private Gee.HashMap<TransformablePhoto, Gdk.Pixbuf> cache = new Gee.HashMap<TransformablePhoto,
        Gdk.Pixbuf>();
    private Gee.ArrayList<TransformablePhoto> lru = new Gee.ArrayList<TransformablePhoto>();
    private Gee.HashMap<TransformablePhoto, FetchJob> in_progress = new Gee.HashMap<TransformablePhoto,
        FetchJob>();
    
    public signal void fetched(TransformablePhoto photo, Gdk.Pixbuf? pixbuf, Error? err);
    
    public PixbufCache(SourceCollection sources, PhotoType type, Scaling scaling, int max_count) {
        this.sources = sources;
        this.type = type;
        this.scaling = scaling;
        this.max_count = max_count;
        
        assert(max_count > 0);
        
        if (background_workers == null)
            background_workers = new Workers(Workers.threads_per_cpu(1), false);
        
        // monitor changes in the photos to discard from cache
        sources.item_altered += on_source_altered;
        sources.items_removed += on_sources_removed;
    }
    
    ~PixbufCache() {
#if TRACE_PIXBUF_CACHE
        debug("Freeing %d pixbufs and cancelling %d jobs", cache.size, in_progress.size);
#endif
        
        sources.item_altered -= on_source_altered;
        sources.items_removed -= on_sources_removed;
        
        foreach (FetchJob job in in_progress.values)
            job.cancel();
    }
    
    public Scaling get_scaling() {
        return scaling;
    }
    
    // This call never blocks.  Returns null if the pixbuf is not present.
    public Gdk.Pixbuf? get_ready_pixbuf(TransformablePhoto photo) {
        return get_cached(photo);
    }
    
    // This call can potentially block if the pixbuf is not in the cache.  Once loaded, it will
    // be cached.  No signal is fired.
    public Gdk.Pixbuf? fetch(TransformablePhoto photo) throws Error {
        Gdk.Pixbuf pixbuf = get_cached(photo);
        if (pixbuf != null) {
#if TRACE_PIXBUF_CACHE
            debug("Fetched in-memory pixbuf for %s @ %s", photo.to_string(), scaling.to_string());
#endif
            
            return pixbuf;
        }
        
        FetchJob? job = in_progress.get(photo);
        if (job != null) {
            job.wait_for_completion();
            if (job.err != null)
                throw job.err;
            
            return job.pixbuf;
        }
        
#if TRACE_PIXBUF_CACHE
        debug("Forced to make a blocking fetch of %s @ %s", photo.to_string(), scaling.to_string());
#endif
        
        pixbuf = photo.get_pixbuf(scaling);
        
        encache(photo, pixbuf);
        
        return pixbuf;
    }
    
    // This can be used to clear specific pixbufs from the cache, allowing finer control over what
    // pixbufs remain and avoid being dropped when other fetches follow.  It implicitly cancels
    // any outstanding prefetches for the photo.
    public void drop(TransformablePhoto photo) {
        cancel_prefetch(photo);
        decache(photo);
    }
    
    // This call signals the cache to pre-load the pixbuf for the photo.  When loaded the fetched
    // signal is fired.
    public void prefetch(TransformablePhoto photo, 
        BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL, bool force = false) {
        if (!force && cache.contains(photo))
            return;
        
        if (in_progress.contains(photo))
            return;
        
        FetchJob job = null;
        switch (type) {
            case PhotoType.REGULAR:
                job = new RegularFetchJob(this, priority, photo, scaling, on_fetched);
            break;
            
            case PhotoType.ORIGINAL:
                job = new OriginalFetchJob(this, priority, photo, scaling, on_fetched);
            break;
            
            default:
                error("Unknown photo type: %d", (int) type);
            break;
        }
        
        in_progress.set(photo, job);
        
        background_workers.enqueue(job);
    }
    
    // This call signals the cache to pre-load the pixbufs for all supplied photos.  Each fires
    // the fetch signal as they arrive.
    public void prefetch_many(Gee.Collection<TransformablePhoto> photos,
        BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL, bool force = false) {
        foreach (TransformablePhoto photo in photos)
            prefetch(photo, priority, force);
    }
    
    public bool cancel_prefetch(TransformablePhoto photo) {
        FetchJob job = in_progress.get(photo);
        if (job == null)
            return false;
        
        // remove here because if fully cancelled the callback is never called
        bool removed = in_progress.unset(photo);
        assert(removed);
        
        job.cancel();
        
#if TRACE_PIXBUF_CACHE
        debug("Cancelled prefetch of %s @ %s", photo.to_string(), scaling.to_string());
#endif
        
        return true;
    }
    
    public void cancel_all() {
#if TRACE_PIXBUF_CACHE
        debug("Cancelling prefetch of %d photos at %s", in_progress.values.size, scaling.to_string());
#endif
        foreach (FetchJob job in in_progress.values)
            job.cancel();
        
        in_progress.clear();
    }
    
    private void on_fetched(BackgroundJob j) {
        FetchJob job = (FetchJob) j;
        
        // remove Cancellable from in_progress list, but don't assert on it because it's possible
        // the cancel was called after the task completed
        in_progress.unset(job.photo);
        
        if (job.err != null) {
            assert(job.pixbuf == null);
            
            critical("Unable to readahead %s: %s", job.photo.to_string(), job.err.message);
            fetched(job.photo, null, job.err);
            
            return;
        }
        
        encache(job.photo, job.pixbuf);
        
        // fire signal
        fetched(job.photo, job.pixbuf, null);
    }
    
    private void on_source_altered(DataObject object) {
        TransformablePhoto photo = object as TransformablePhoto;
        assert(photo != null);
        
        // only interested if in this cache and not an originals cache, as they never alter
        if (!cache.contains(photo) && type != PhotoType.ORIGINAL)
            return;
        
        decache(photo);
        
#if TRACE_PIXBUF_CACHE
        debug("Re-fetching altered pixbuf from cache: %s @ %s", photo.to_string(), scaling.to_string());
#endif
        
        prefetch(photo, BackgroundJob.JobPriority.HIGH);
    }
    
    private void on_sources_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            TransformablePhoto photo = object as TransformablePhoto;
            assert(photo != null);
            
            decache(photo);
        }
    }
    
    private Gdk.Pixbuf? get_cached(TransformablePhoto photo) {
        Gdk.Pixbuf pixbuf = cache.get(photo);
        if (pixbuf == null)
            return null;
        
        // move up in the LRU
        int index = lru.index_of(photo);
        assert(index >= 0);
        
        if (index > 0) {
            lru.remove_at(index);
            lru.insert(0, photo);
        }
        
        return pixbuf;
    }
    
    private void encache(TransformablePhoto photo, Gdk.Pixbuf pixbuf) {
        // if already in cache, remove (means it was re-fetched, probably due to modification)
        decache(photo);
        
        cache.set(photo, pixbuf);
        lru.insert(0, photo);
        
        while (lru.size > max_count) {
            TransformablePhoto cached_photo = lru.remove_at(lru.size - 1);
            assert(cached_photo != null);
            
            bool removed = cache.unset(cached_photo);
            assert(removed);
        }
        
        assert(lru.size == cache.size);
    }
    
    private void decache(TransformablePhoto photo) {
        if (!cache.remove(photo)) {
            assert(!lru.contains(photo));
            
            return;
        }
        
        bool removed = lru.remove(photo);
        assert(removed);
    }
}

