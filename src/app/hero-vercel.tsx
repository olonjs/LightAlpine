"use client";

import { ArrowRight } from "lucide-react";
import {
  type MotionValue,
  motion,
  useInView,
  useMotionTemplate,
  useMotionValue,
  useReducedMotion,
  useSpring,
  type Variants,
} from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";

import { TextScramble } from "../../marketing-bento-vercel/vercel-bento/text-scramble";
import { CircuitBoard } from "./circuit-board";

const spring = { type: "spring" as const, stiffness: 300, damping: 24 };

const staggerContainer: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.1,
    },
  },
};

const fadeUp: Variants = {
  hidden: { opacity: 0, y: 20, filter: "blur(8px)" },
  visible: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: spring,
  },
};

const wordStagger: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.06,
      delayChildren: 0,
    },
  },
};

const wordFadeUp: Variants = {
  hidden: { opacity: 0, y: 12, filter: "blur(6px)" },
  visible: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: spring,
  },
};

/* ─── Mouse-reactive glow ─── */

function GlowOrb({ mouseX, mouseY }: { mouseX: MotionValue<number>; mouseY: MotionValue<number> }) {
  const prefersReducedMotion = useReducedMotion();

  const smoothX = useSpring(mouseX, { stiffness: 50, damping: 40 });
  const smoothY = useSpring(mouseY, { stiffness: 50, damping: 40 });

  const background = useMotionTemplate`radial-gradient(
    600px circle at ${smoothX}px ${smoothY}px,
    hsl(var(--foreground) / 0.04),
    transparent 60%
  )`;

  if (prefersReducedMotion) {
    return (
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background: "radial-gradient(600px circle at 50% 30%, hsl(var(--foreground) / 0.04), transparent 60%)",
        }}
      />
    );
  }

  return <motion.div className="pointer-events-none absolute inset-0" style={{ background }} />;
}

/* ─── Stats data ─── */

const STATS = [
  { value: 200, suffix: "ms", label: "Avg. deploy time", decimals: 0 },
  { value: 99.99, suffix: "%", label: "Uptime SLA", decimals: 2 },
  { value: 300, suffix: "+", label: "Edge locations", decimals: 0 },
  { value: 50, suffix: "M+", label: "Deploys / week", decimals: 0 },
];

function AnimatedCounter({ value, suffix = "", decimals = 0 }: { value: number; suffix?: string; decimals?: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const motionValue = useMotionValue(0);
  const springValue = useSpring(motionValue, { stiffness: 75, damping: 25 });
  const isInView = useInView(ref, { once: true, margin: "-100px" });

  useEffect(() => {
    if (isInView) {
      motionValue.set(value);
    }
  }, [isInView, motionValue, value]);

  useEffect(() => {
    const unsubscribe = springValue.on("change", (v) => {
      if (ref.current) {
        const formatted = decimals > 0 ? v.toFixed(decimals) : Math.round(v).toLocaleString();
        ref.current.textContent = `${formatted}${suffix}`;
      }
    });
    return unsubscribe;
  }, [springValue, suffix, decimals]);

  const initial = decimals > 0 ? `${(0).toFixed(decimals)}${suffix}` : `0${suffix}`;

  return (
    <span className="tabular-nums" ref={ref}>
      {initial}
    </span>
  );
}

function StatCell({
  value,
  suffix,
  label,
  decimals,
  isLast,
}: {
  value: number;
  suffix: string;
  label: string;
  decimals: number;
  isLast: boolean;
}) {
  const [hoverKey, setHoverKey] = useState(0);

  return (
    <div
      className={`flex flex-col items-center justify-center gap-2 border-border border-b p-8 text-center transition-colors hover:bg-secondary/50 md:border-b-0 md:p-12 ${isLast ? "" : "md:border-r"}`}
      onMouseEnter={() => setHoverKey((k) => k + 1)}
    >
      <span className="font-bold text-3xl text-foreground tracking-tight sm:text-4xl md:text-5xl">
        <AnimatedCounter decimals={decimals} suffix={suffix} value={value} />
      </span>
      <TextScramble
        as="span"
        className="text-muted-foreground text-sm"
        duration={0.4}
        key={hoverKey}
        speed={0.03}
        trigger={hoverKey > 0}
      >
        {label}
      </TextScramble>
    </div>
  );
}

/* ─── Main hero ─── */

export function HeroVercel() {
  const [pillHovered, setPillHovered] = useState(false);
  const mouseX = useMotionValue(0);
  const mouseY = useMotionValue(0);
  const prefersReducedMotion = useReducedMotion();

  const handleMouseMove = useCallback(
    (e: React.MouseEvent<HTMLElement>) => {
      if (prefersReducedMotion) {
        return;
      }
      const rect = e.currentTarget.getBoundingClientRect();
      mouseX.set(e.clientX - rect.left);
      mouseY.set(e.clientY - rect.top);
    },
    [mouseX, mouseY, prefersReducedMotion]
  );

  return (
    <section className="relative w-full overflow-hidden bg-background" onMouseMove={handleMouseMove}>
      {/* ── Background ── */}
      <div className="pointer-events-none absolute inset-0">
        {/* Primary radial glow */}
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_60%_50%_at_50%_0%,rgba(0,0,0,0.04),transparent)] dark:bg-[radial-gradient(ellipse_60%_50%_at_50%_0%,rgba(255,255,255,0.03),transparent)]" />
        {/* Mouse-reactive glow */}
        <GlowOrb mouseX={mouseX} mouseY={mouseY} />
        {/* Dot grid */}
        <div
          className="absolute inset-0 opacity-[0.35] dark:opacity-[0.12]"
          style={{
            backgroundImage: "radial-gradient(circle at center, hsl(var(--foreground) / 0.07) 1px, transparent 1px)",
            backgroundSize: "24px 24px",
          }}
        />
        {/* Edge fades */}
        <div className="absolute inset-x-0 top-0 h-40 bg-gradient-to-b from-background to-transparent" />
        <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-background to-transparent" />
      </div>

      {/* ── Content ── */}
      <motion.div
        animate="visible"
        className="relative z-10 mx-auto flex max-w-3xl flex-col items-center px-6 pt-[14vh] pb-20 sm:pt-[18vh]"
        initial="hidden"
        variants={staggerContainer}
      >
        {/* Announcement pill */}
        <motion.div variants={fadeUp}>
          <button
            className="group mb-8 inline-flex cursor-pointer items-center gap-2.5 rounded-full bg-background px-4 py-2 text-sm shadow-[0px_0px_0px_1px_rgba(0,0,0,0.06),0px_1px_2px_-1px_rgba(0,0,0,0.05)] transition-shadow duration-200 hover:shadow-[0px_0px_0px_1px_rgba(0,0,0,0.08),0px_1px_2px_-1px_rgba(0,0,0,0.08),0px_2px_4px_0px_rgba(0,0,0,0.06)] dark:shadow-[0px_0px_0px_1px_rgba(255,255,255,0.08),0px_1px_2px_-1px_rgba(255,255,255,0.04)] dark:hover:shadow-[0px_0px_0px_1px_rgba(255,255,255,0.1),0px_1px_2px_-1px_rgba(255,255,255,0.05),0px_2px_4px_0px_rgba(0,0,0,0.25)]"
            onMouseEnter={() => setPillHovered(true)}
            onMouseLeave={() => setPillHovered(false)}
          >
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
            </span>
            <TextScramble
              as="span"
              className="font-medium text-foreground"
              duration={0.5}
              speed={0.03}
              trigger={pillHovered}
            >
              Introducing v2.0
            </TextScramble>
            <ChevronRightIcon className="h-3.5 w-3.5 text-muted-foreground transition-transform duration-200 group-hover:translate-x-0.5" />
          </button>
        </motion.div>

        {/* Headline — word-level stagger */}
        <motion.h1
          className="mb-6 flex flex-wrap justify-center text-center font-bold text-4xl leading-[1.08] tracking-[-0.035em] sm:text-5xl md:text-6xl lg:text-7xl"
          variants={wordStagger}
        >
          {"Your complete platform".split(" ").map((word, i) => (
            <motion.span className="mr-[0.28em] inline-block text-foreground" key={i} variants={wordFadeUp}>
              {word}
            </motion.span>
          ))}
          {"for the web.".split(" ").map((word, i) => (
            <motion.span
              className="mr-[0.28em] inline-block text-muted-foreground"
              key={`m-${i}`}
              variants={wordFadeUp}
            >
              {word}
            </motion.span>
          ))}
        </motion.h1>

        {/* Subtitle */}
        <motion.p
          className="mb-10 max-w-xl text-pretty text-center text-base text-muted-foreground leading-relaxed sm:text-lg"
          variants={fadeUp}
        >
          Vercel provides the developer tools and cloud infrastructure to build, scale, and secure a faster, more
          personalized web.
        </motion.p>

        {/* CTA buttons */}
        <motion.div className="flex flex-col items-center gap-3 sm:flex-row sm:gap-4" variants={fadeUp}>
          <motion.button
            className="group relative inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-full bg-foreground px-6 py-3 font-medium text-background text-sm transition-shadow duration-200 hover:shadow-[0_8px_30px_rgb(0,0,0,0.12)] sm:w-auto dark:hover:shadow-[0_8px_30px_rgb(255,255,255,0.06)]"
            transition={spring}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
          >
            Start Deploying
            <ArrowRight
              className="size-4 transition-transform duration-200 group-hover:translate-x-0.5"
              strokeWidth={2}
            />
          </motion.button>
          <motion.button
            className="group inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border border-border bg-background px-6 py-3 font-medium text-foreground text-sm transition-all duration-200 hover:bg-secondary sm:w-auto"
            transition={spring}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
          >
            Get a Demo
            <ArrowRight
              className="size-4 text-muted-foreground transition-transform duration-200 group-hover:translate-x-0.5"
              strokeWidth={2}
            />
          </motion.button>
        </motion.div>
      </motion.div>

      {/* ── Circuit board bridge ── */}
      <motion.div
        animate={{ opacity: 1, y: 0 }}
        className="relative z-10 mx-auto w-full max-w-5xl px-6 pb-16"
        initial={{ opacity: 0, y: 20 }}
        transition={{ duration: 0.6, delay: 0.4 }}
      >
        <CircuitBoard />
      </motion.div>

      {/* ── Stats grid ── */}
      <motion.div
        animate={{ opacity: 1, y: 0 }}
        className="relative z-10 w-full border-border border-y"
        initial={{ opacity: 0, y: 16 }}
        transition={{ duration: 0.5, delay: 0.5 }}
      >
        <div className="grid grid-cols-2 md:grid-cols-4">
          {STATS.map((stat, i) => (
            <StatCell
              decimals={stat.decimals}
              isLast={i === STATS.length - 1}
              key={stat.label}
              label={stat.label}
              suffix={stat.suffix}
              value={stat.value}
            />
          ))}
        </div>
      </motion.div>
    </section>
  );
}

function ChevronRightIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth={2}
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="m9 18 6-6-6-6" />
    </svg>
  );
}
