# Design System & Visual Specification

<!-- impeccable:design-schema 1 -->

## Design Philosophy: shadcn Minimalist Precision

Inspired by shadcn/ui and modern engineering tools (Vercel, GitHub, Linear, Cloudflare), the visual identity prioritizes clarity, legibility, and technical honesty.

### Rules of Engagement
- **No Glowing Logos or Neon Halos**: Depth is created with subtle 1px border contrast (`var(--border)`) and soft, natural ambient drop-shadows.
- **No Gradient Text or Hyperbolic Buzzwords**: Headings speak with size, font weight, and structural positioning.
- **Authored SVG Icons Only**: No emoji icons or Unicode glyph substitutions. Every icon is a consistent 1.75px stroke SVG.
- **Matter-of-Fact Copy**: Exact supported formats, exact local execution methods, transparent platform requirements.
- **Essential Footer Links**: Clean, structured navigation for Documentation, GitHub, Apache 2.0 License, Issues, and Sponsorship.

---

## Token Architecture

```css
:root {
  /* Light Mode (Zinc) */
  --background: #ffffff;
  --foreground: #09090b;
  --card: #ffffff;
  --card-foreground: #09090b;
  --popover: #ffffff;
  --popover-foreground: #09090b;
  --primary: #18181b;
  --primary-foreground: #fafafa;
  --secondary: #f4f4f5;
  --secondary-foreground: #18181b;
  --muted: #f4f4f5;
  --muted-foreground: #71717a;
  --accent: #f4f4f5;
  --accent-foreground: #18181b;
  --destructive: #ef4444;
  --destructive-foreground: #fafafa;
  --border: #e4e4e7;
  --input: #e4e4e7;
  --ring: #18181b;
  --radius: 0.5rem;
}

[data-theme="dark"] {
  /* Dark Mode (Default / Zinc) */
  --background: #09090b;
  --foreground: #fafafa;
  --card: #09090b;
  --card-foreground: #fafafa;
  --popover: #09090b;
  --popover-foreground: #fafafa;
  --primary: #fafafa;
  --primary-foreground: #18181b;
  --secondary: #27272a;
  --secondary-foreground: #fafafa;
  --muted: #27272a;
  --muted-foreground: #a1a1aa;
  --accent: #27272a;
  --accent-foreground: #fafafa;
  --destructive: #7f1d1d;
  --destructive-foreground: #fafafa;
  --border: #27272a;
  --input: #27272a;
  --ring: #d4d4d8;
  --radius: 0.5rem;
}
```

---

## Typography Hierarchy

- **Font Family**: `Inter`, `-apple-system`, `BlinkMacSystemFont`, `"Segoe UI"`, `Roboto`, sans-serif.
- **Monospace**: `JetBrains Mono`, `ui-monospace`, `monospace` (reserved for file extensions, CLI commands, and technical specifications).
- **Scale**:
  - `Display / H1`: `2.75rem` (44px) / Line height `1.15` / Weight `700` / Letter spacing `-0.025em`
  - `H2`: `1.75rem` (28px) / Line height `1.25` / Weight `600` / Letter spacing `-0.02em`
  - `H3`: `1.25rem` (20px) / Line height `1.4` / Weight `600` / Letter spacing `-0.01em`
  - `Body`: `1rem` (16px) / Line height `1.6` / Weight `400` / Color `var(--muted-foreground)`
  - `Small / Badge`: `0.75rem` (12px) / Line height `1rem` / Weight `500`

---

## Component Standards

### 1. Button (`.btn`)
- **Primary**: Solid `var(--primary)` background, `var(--primary-foreground)` text, `6px` radius, crisp hover transition.
- **Outline / Secondary**: 1px solid `var(--border)`, background transparent or `var(--secondary)`, subtle focus ring.

### 2. Badge / Tag (`.badge`)
- Inline flex container, `padding: 2px 8px`, `border: 1px solid var(--border)`, `font-family: monospace`, `font-size: 12px`, muted colors.

### 3. Card / Section Container
- Solid background `var(--card)`, 1px border `var(--border)`, radius `var(--radius)`, clean padding without nested cards.

