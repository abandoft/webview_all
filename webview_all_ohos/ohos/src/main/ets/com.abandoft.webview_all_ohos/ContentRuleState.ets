// Synchronous native URL rules; no Dart or JavaScript is involved in matching.
export class ContentRuleState {
  private patterns: Array<string> = [];
  private actions: Array<boolean> = [];
  private sensitive: Array<boolean> = [];

  configure(rules: Array<Map<string, ESObject>>): void {
    if (rules.length > 256) throw new Error('At most 256 content rules are supported.');
    const patterns: Array<string> = [];
    const actions: Array<boolean> = [];
    const sensitive: Array<boolean> = [];
    rules.forEach((rule: Map<string, ESObject>) => {
      const pattern = rule.get('urlPattern') as string;
      const types = rule.get('resourceTypes') as Array<string>;
      const action = rule.get('action') as string;
      if (!pattern || pattern.length > 2048 || pattern.split('*').length > 33 || /[^\x20-\x7e]/.test(pattern) ||
          types.length > 0 || (action !== 'block' && action !== 'allow'))
        throw new Error('This content-rule set is invalid; resource-type filtering is unavailable.');
      patterns.push(pattern); actions.push(action === 'block'); sensitive.push(rule.get('caseSensitive') === true);
    });
    this.patterns = patterns; this.actions = actions; this.sensitive = sensitive;
  }
  private matches(pattern: string, url: string, sensitive: boolean): boolean {
    const value = sensitive ? url : url.toLowerCase();
    const parts = (sensitive ? pattern : pattern.toLowerCase()).split('*');
    if (parts.length === 1) return parts[0] === value;
    if (!value.startsWith(parts[0]) || !value.endsWith(parts[parts.length - 1])) return false;
    let cursor = parts[0].length;
    const end = value.length - parts[parts.length - 1].length;
    if (cursor > end) return false;
    for (let i = 1; i < parts.length - 1; i++) {
      const found = value.indexOf(parts[i], cursor);
      if (found < 0 || found + parts[i].length > end) return false;
      cursor = found + parts[i].length;
    }
    return true;
  }
  blocks(url: string): boolean {
    let blocked = false;
    for (let i = 0; i < this.patterns.length; i++) {
      if (this.matches(this.patterns[i], url, this.sensitive[i])) blocked = this.actions[i];
    }
    return blocked;
  }
}
