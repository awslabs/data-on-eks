/**
 * Custom Icon Component System
 *
 * Provides consistent, professional SVG icons throughout the site
 * Using Lucide Icons library (MIT license, 1000+ icons)
 */

import React from 'react';
import {
  Zap,
  Target,
  Lock,
  DollarSign,
  BarChart3,
  Cloud,
  Rocket,
  BookOpen,
  Package,
  Cpu,
  Waves,
  GitBranch,
  Database,
  GraduationCap,
  Settings,
  Activity,
  Server,
  HardDrive,
  Boxes,
  Link2,
  Wrench,
  CheckCircle2,
  AlertCircle,
  Info,
  Sparkles,
  Users,
  Globe,
  ArrowRight,
  ExternalLink,
  Github,
  MessageCircle,
  FileText,
  Bug,
  Lightbulb,
  TrendingUp,
  Shield,
  Key,
  Network,
  Workflow,
  Code,
  Terminal,
  Container,
  Layers,
  Gauge,
  FlaskConical,
  Microscope,
  Factory,
  Truck,
  Disc,
  HardDriveDownload,
  CircuitBoard,
  Braces,
  Binary,
  Hash,
  Blocks
} from 'lucide-react';

// Icon wrapper component for consistent sizing and styling
export function Icon({ icon: IconComponent, size = 24, className = '', ...props }) {
  return (
    <IconComponent
      size={size}
      className={className}
      strokeWidth={2}
      {...props}
    />
  );
}

// Predefined icon components for common use cases
export const Icons = {
  // Brand & Hero
  zap: Zap,
  rocket: Rocket,
  sparkles: Sparkles,

  // Design Principles
  target: Target,
  lock: Lock,
  dollarSign: DollarSign,
  barChart: BarChart3,

  // Technology
  cloud: Cloud,
  server: Server,
  cpu: Cpu,
  database: Database,
  hardDrive: HardDrive,
  container: Container,
  network: Network,
  circuitBoard: CircuitBoard,

  // Data Stack Categories
  settings: Settings,      // Processing
  waves: Waves,            // Streaming
  gitBranch: GitBranch,    // Orchestration
  disc: Disc,              // Databases
  graduationCap: GraduationCap, // Workshops

  // Infrastructure
  boxes: Boxes,
  layers: Layers,
  workflow: Workflow,
  wrench: Wrench,

  // Features
  checkCircle: CheckCircle2,
  alertCircle: AlertCircle,
  info: Info,
  link: Link2,

  // Navigation
  arrowRight: ArrowRight,
  externalLink: ExternalLink,
  bookOpen: BookOpen,

  // Community
  github: Github,
  messageCircle: MessageCircle,
  users: Users,
  bug: Bug,

  // Content
  fileText: FileText,
  code: Code,
  terminal: Terminal,

  // Metrics & Performance
  activity: Activity,
  trendingUp: TrendingUp,
  gauge: Gauge,

  // Security
  shield: Shield,
  key: Key,

  // Resources
  lightbulb: Lightbulb,
  globe: Globe,

  // Development
  flaskConical: FlaskConical,
  microscope: Microscope,
  factory: Factory,

  // Data Processing
  package: Package,
  truck: Truck,
  hardDriveDownload: HardDriveDownload,
  braces: Braces,
  binary: Binary,
  hash: Hash,
  blocks: Blocks,
};

// Icon with background (for hero sections and featured items)
export function IconWithBackground({
  icon: IconComponent,
  size = 48,
  gradient = 'from-purple-500 to-pink-500',
  className = ''
}) {
  return (
    <div
      className={`inline-flex items-center justify-center rounded-2xl bg-gradient-to-br ${gradient} p-3 shadow-lg ${className}`}
      style={{
        boxShadow: '0 8px 25px rgba(102, 126, 234, 0.3)'
      }}
    >
      <IconComponent
        size={size}
        color="white"
        strokeWidth={2}
      />
    </div>
  );
}

// Animated icon (for interactive elements)
export function AnimatedIcon({
  icon: IconComponent,
  size = 24,
  className = '',
  ...props
}) {
  return (
    <IconComponent
      size={size}
      className={`transition-all duration-300 ease-in-out ${className}`}
      strokeWidth={2}
      {...props}
    />
  );
}

export default Icons;
