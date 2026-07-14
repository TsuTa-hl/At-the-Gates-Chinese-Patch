using System;
using System.Runtime.CompilerServices;
using Microsoft.Xna.Framework.Graphics;

namespace AtG.RuntimeText
{
    public static class SpriteBatchLifecycle
    {
        private sealed class BatchState
        {
            public bool Active;
        }

        private static readonly ConditionalWeakTable<SpriteBatch, BatchState> States =
            new ConditionalWeakTable<SpriteBatch, BatchState>();

        public static void Begin(SpriteBatch batch)
        {
            if (batch == null) throw new ArgumentNullException("batch");
            FlushPending(batch);
            batch.Begin();
            SetActive(batch, true);
        }

        public static void Begin(SpriteBatch batch, SpriteSortMode sortMode,
            BlendState blendState, SamplerState samplerState,
            DepthStencilState depthStencilState, RasterizerState rasterizerState)
        {
            if (batch == null) throw new ArgumentNullException("batch");
            FlushPending(batch);
            batch.Begin(sortMode, blendState, samplerState, depthStencilState, rasterizerState);
            SetActive(batch, true);
        }

        public static void Begin(SpriteBatch batch, SpriteSortMode sortMode,
            BlendState blendState, SamplerState samplerState,
            DepthStencilState depthStencilState, RasterizerState rasterizerState,
            Effect effect)
        {
            if (batch == null) throw new ArgumentNullException("batch");
            FlushPending(batch);
            batch.Begin(sortMode, blendState, samplerState, depthStencilState, rasterizerState, effect);
            SetActive(batch, true);
        }

        public static void End(SpriteBatch batch)
        {
            if (batch == null) throw new ArgumentNullException("batch");
            var completed = false;
            try
            {
                batch.End();
                completed = true;
            }
            finally
            {
                SetActive(batch, false);
            }
            if (completed) FlushPending(batch);
        }

        internal static bool IsActive(SpriteBatch batch)
        {
            BatchState state;
            return batch != null && States.TryGetValue(batch, out state) && state.Active;
        }

        private static void SetActive(SpriteBatch batch, bool active)
        {
            States.GetValue(batch, ignored => new BatchState()).Active = active;
        }

        private static void FlushPending(SpriteBatch batch)
        {
            GlyphAtlasRegistry.FlushPending(batch.GraphicsDevice);
        }
    }
}
