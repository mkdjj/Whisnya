export const BRIDGE_PROTOCOL_VERSION = "1";

export function authenticatedHeaders(token: string): Record<string, string> {
  return {
    authorization: `Bearer ${token}`,
    "x-whisnya-bridge-version": BRIDGE_PROTOCOL_VERSION,
  };
}
