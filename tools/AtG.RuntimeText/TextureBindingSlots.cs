using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    internal static class TextureBindingSlots
    {
        public static int[] FindReferenceSlots<T>(T target, int slotCount,
            Func<int, T> getTexture) where T : class
        {
            if (target == null) throw new ArgumentNullException("target");
            if (slotCount < 0) throw new ArgumentOutOfRangeException("slotCount");
            if (getTexture == null) throw new ArgumentNullException("getTexture");

            var matches = new List<int>();
            for (var slot = 0; slot < slotCount; slot++)
            {
                if (ReferenceEquals(getTexture(slot), target)) matches.Add(slot);
            }
            return matches.ToArray();
        }
    }
}
