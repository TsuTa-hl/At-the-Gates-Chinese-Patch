using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    internal sealed class PriorityDeduplicatingQueue<T>
    {
        private sealed class Entry
        {
            public string Key;
            public T Item;
            public int Priority;
            public LinkedListNode<Entry> Node;
        }

        private readonly int _maximumCount;
        private readonly LinkedList<Entry>[] _queues;
        private readonly Dictionary<string, Entry> _entries =
            new Dictionary<string, Entry>(StringComparer.Ordinal);

        public PriorityDeduplicatingQueue(int priorityCount, int maximumCount)
        {
            if (priorityCount <= 0) throw new ArgumentOutOfRangeException("priorityCount");
            if (maximumCount <= 0) throw new ArgumentOutOfRangeException("maximumCount");
            _maximumCount = maximumCount;
            _queues = new LinkedList<Entry>[priorityCount];
            for (var index = 0; index < _queues.Length; index++)
                _queues[index] = new LinkedList<Entry>();
        }

        public int Count { get { return _entries.Count; } }

        public bool Enqueue(string key, T item, int priority)
        {
            if (key == null) throw new ArgumentNullException("key");
            ValidatePriority(priority);
            Entry existing;
            if (_entries.TryGetValue(key, out existing))
            {
                if (priority < existing.Priority) Promote(existing, priority);
                return false;
            }
            if (_entries.Count >= _maximumCount) return false;

            var entry = new Entry
            {
                Key = key,
                Item = item,
                Priority = priority,
            };
            entry.Node = _queues[priority].AddLast(entry);
            _entries.Add(key, entry);
            return true;
        }

        public bool Promote(string key, int priority)
        {
            if (key == null) throw new ArgumentNullException("key");
            ValidatePriority(priority);
            Entry entry;
            if (!_entries.TryGetValue(key, out entry) || priority >= entry.Priority)
                return false;
            Promote(entry, priority);
            return true;
        }

        public bool TryPeek(out string key, out T item, out int priority)
        {
            for (var queueIndex = 0; queueIndex < _queues.Length; queueIndex++)
            {
                var node = _queues[queueIndex].First;
                if (node == null) continue;
                var entry = node.Value;
                key = entry.Key;
                item = entry.Item;
                priority = entry.Priority;
                return true;
            }
            key = null;
            item = default(T);
            priority = 0;
            return false;
        }

        public bool TryDequeue(out string key, out T item, out int priority)
        {
            for (var queueIndex = 0; queueIndex < _queues.Length; queueIndex++)
            {
                var node = _queues[queueIndex].First;
                if (node == null) continue;
                var entry = node.Value;
                _queues[queueIndex].Remove(node);
                _entries.Remove(entry.Key);
                key = entry.Key;
                item = entry.Item;
                priority = entry.Priority;
                return true;
            }
            key = null;
            item = default(T);
            priority = 0;
            return false;
        }

        public void Clear()
        {
            foreach (var queue in _queues) queue.Clear();
            _entries.Clear();
        }

        private void Promote(Entry entry, int priority)
        {
            _queues[entry.Priority].Remove(entry.Node);
            entry.Priority = priority;
            entry.Node = _queues[priority].AddLast(entry);
        }

        private void ValidatePriority(int priority)
        {
            if (priority < 0 || priority >= _queues.Length)
                throw new ArgumentOutOfRangeException("priority");
        }
    }
}
