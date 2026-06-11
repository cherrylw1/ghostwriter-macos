import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        background: "#110D0A",
        surface: "#1A1410",
        elevated: "#221C17",
        border: {
          subtle: "#2A2118",
          default: "#3D3028",
        },
        accent: {
          DEFAULT: "#D4900C",
          hover: "#E8A020",
          muted: "#7A5208",
          subtle: "#2A1E08",
        },
        text: {
          primary: "#F5F0EB",
          secondary: "#9E9189",
          muted: "#6B5E54",
          inverse: "#110D0A",
      },
      },
      fontFamily: {
        display: ["var(--font-playfair)", "Georgia", "serif"],
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "monospace"],
      },
      fontSize: {
        "display-xl": ["clamp(64px, 8vw, 112px)", { lineHeight: "1.02", letterSpacing: "-0.03em" }],
        "display-lg": ["clamp(48px, 6vw, 80px)", { lineHeight: "1.05", letterSpacing: "-0.025em" }],
        "display-md": ["clamp(32px, 4vw, 52px)", { lineHeight: "1.1", letterSpacing: "-0.02em" }],
        "body-xl": ["20px", { lineHeight: "1.6", letterSpacing: "-0.01em" }],
        "body-lg": ["18px", { lineHeight: "1.65", letterSpacing: "-0.005em" }],
        "body-md": ["16px", { lineHeight: "1.7" }],
        "body-sm": ["14px", { lineHeight: "1.6" }],
        "label": ["11px", { lineHeight: "1.4", letterSpacing: "0.1em" }],
      },
      spacing: {
        "section": "clamp(80px, 12vh, 140px)",
        "section-sm": "clamp(48px, 8vh, 80px)",
      },
      transitionTimingFunction: {
        "recognition": "cubic-bezier(0.25, 0.1, 0.25, 1.0)",
      },
      transitionDuration: {
        "recognition": "250ms",
      },
      animation: {
        "fade-in": "fadeIn 250ms cubic-bezier(0.25, 0.1, 0.25, 1.0) forwards",
      },
      keyframes: {
        fadeIn: {
          "0%": { opacity: "0", transform: "translateY(4px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
      },
    },
  },
  plugins: [],
};

export default config;
