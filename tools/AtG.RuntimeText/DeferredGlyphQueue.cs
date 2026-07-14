using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    internal sealed class DeferredGlyphQueue<T>
    {
        private readonly object _gate = new object();
        private readonly HashSet<string> _keys = new HashSet<string>(StringComparer.Ordinal);
        private readonly List<T> _items = new List<T>();

        public int Count { get { lock (_gate) return _items.Count; } }

        public bool Enqueue(string key, T item)
        {
            if (key == null) throw new ArgumentNullException("key");
            lock (_gate)
            {
                if (!_keys.Add(key)) return false;
                _items.Add(item);
                return true;
            }
        }

        public IList<T> Drain()
        {
            lock (_gate)
            {
                if (_items.Count == 0) return new List<T>();
                var drained = new List<T>(_items);
                _items.Clear();
                _keys.Clear();
                return drained;
            }
        }
    }
}
