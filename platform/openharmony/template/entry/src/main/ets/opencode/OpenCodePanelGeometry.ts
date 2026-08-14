export const OPENCODE_PANEL_ANCHOR_ID = 'opencode-editor-panel-anchor';
export const OPENCODE_PANEL_EXPANDED_MIN_WIDTH = 768;

const MAX_SURFACE_COORDINATE = 32768;
const MAX_SURFACE_EXTENT = 16384;

export interface OpenCodePanelBounds {
  left: number;
  top: number;
  width: number;
  height: number;
}

export type OpenCodePanelPresentation = 'compact' | 'expanded';

/**
 * Mirrors the upstream client's desktop media-query boundary. The ArkWeb
 * viewport remains authoritative; this classification is host-visible state
 * used to verify compact/expanded resize transitions.
 */
export function classifyOpenCodePanelWidth(width: number):
  OpenCodePanelPresentation {
  return width >= OPENCODE_PANEL_EXPANDED_MIN_WIDTH ? 'expanded' : 'compact';
}

export function normalizeOpenCodePanelAnchorBounds(left: number, top: number,
  width: number, height: number): OpenCodePanelBounds | undefined {
  if (!Number.isInteger(left) || !Number.isInteger(top) ||
    !Number.isInteger(width) || !Number.isInteger(height) ||
    left < 0 || top < 0 ||
    left > MAX_SURFACE_COORDINATE || top > MAX_SURFACE_COORDINATE ||
    width < 1 || height < 1 ||
    width > MAX_SURFACE_EXTENT || height > MAX_SURFACE_EXTENT) {
    return undefined;
  }
  return { left, top, width, height };
}
