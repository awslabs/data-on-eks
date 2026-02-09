/**
 * Colorful Icon Component System using IconPark
 *
 * IconPark provides beautiful multi-colored icons perfect for modern web design
 * All icons support multiple themes: outline, filled, two-tone, and multi-colored
 */

import React from 'react';
import {
  Lightning,
  Target,
  Lock,
  MoneyBox,
  TrendingUp,
  CloudStorage,
  Code,
  Magic,
  Rocket,
  BookOpen,
  Config,
  Wave,
  Branch,
  DatabaseNetwork,
  GraduationCap,
  Connection,
  EveryUser,
  Earth,
  CheckOne,
  Microscope,
  LabFlask,
  Bug,
  Comments,
  Github as GithubIcon,
  Analysis,
  ArrowRight,
  Setting
} from '@icon-park/react';

// Colorful icon with gradient background wrapper
export function ColorfulIcon({ icon: IconComponent, size = 24, theme = 'multi-color', className = '', ...props }) {
  return (
    <IconComponent
      size={size}
      theme={theme}
      fill={theme === 'multi-color' ? ['#667eea', '#764ba2', '#f093fb', '#f5576c'] : undefined}
      strokeWidth={3}
      className={className}
      {...props}
    />
  );
}

// Predefined colorful icon components
export const ColorfulIcons = {
  // Brand & Hero
  lightning: (props) => <Lightning theme="multi-color" fill={['#FFD700', '#FF6B6B', '#4ECDC4', '#45B7D1']} {...props} />,
  rocket: (props) => <Rocket theme="multi-color" fill={['#667eea', '#764ba2', '#f093fb', '#f5576c']} {...props} />,
  magic: (props) => <Magic theme="multi-color" fill={['#FFD700', '#FF6B6B', '#9D4EDD', '#4ECDC4']} {...props} />,

  // Design Principles
  target: (props) => <Target theme="multi-color" fill={['#667eea', '#764ba2', '#f093fb', '#f5576c']} {...props} />,
  lock: (props) => <Lock theme="multi-color" fill={['#10b981', '#34d399', '#6ee7b7', '#a7f3d0']} {...props} />,
  moneyBox: (props) => <MoneyBox theme="multi-color" fill={['#f59e0b', '#fbbf24', '#fcd34d', '#fde68a']} {...props} />,
  analysis: (props) => <Analysis theme="multi-color" fill={['#3b82f6', '#60a5fa', '#93c5fd', '#dbeafe']} {...props} />,

  // Technology
  cloudStorage: (props) => <CloudStorage theme="multi-color" fill={['#667eea', '#764ba2', '#f093fb', '#f5576c']} {...props} />,
  code: (props) => <Code theme="multi-color" fill={['#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe']} {...props} />,
  config: (props) => <Config theme="multi-color" fill={['#ef4444', '#f87171', '#fca5a5', '#fecaca']} {...props} />,

  // Data Stack Categories
  setting: (props) => <Setting theme="multi-color" fill={['#667eea', '#764ba2', '#f093fb', '#f5576c']} {...props} />,
  wave: (props) => <Wave theme="multi-color" fill={['#06b6d4', '#22d3ee', '#67e8f9', '#a5f3fc']} {...props} />,
  branch: (props) => <Branch theme="multi-color" fill={['#14b8a6', '#2dd4bf', '#5eead4', '#99f6e4']} {...props} />,
  databaseNetwork: (props) => <DatabaseNetwork theme="multi-color" fill={['#10b981', '#34d399', '#6ee7b7', '#a7f3d0']} {...props} />,
  graduationCap: (props) => <GraduationCap theme="multi-color" fill={['#f59e0b', '#fbbf24', '#fcd34d', '#fde68a']} {...props} />,

  // Features
  connection: (props) => <Connection theme="multi-color" fill={['#3b82f6', '#60a5fa', '#93c5fd', '#dbeafe']} {...props} />,
  checkOne: (props) => <CheckOne theme="multi-color" fill={['#10b981', '#34d399', '#6ee7b7', '#a7f3d0']} {...props} />,

  // Community
  everyUser: (props) => <EveryUser theme="multi-color" fill={['#ec4899', '#f472b6', '#f9a8d4', '#fbcfe8']} {...props} />,
  earth: (props) => <Earth theme="multi-color" fill={['#06b6d4', '#22d3ee', '#67e8f9', '#a5f3fc']} {...props} />,

  // Navigation
  arrowRight: (props) => <ArrowRight theme="filled" fill={['#667eea']} {...props} />,
  bookOpen: (props) => <BookOpen theme="multi-color" fill={['#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe']} {...props} />,

  // Resources
  labFlask: (props) => <LabFlask theme="multi-color" fill={['#10b981', '#34d399', '#6ee7b7', '#a7f3d0']} {...props} />,
  microscope: (props) => <Microscope theme="multi-color" fill={['#ec4899', '#f472b6', '#f9a8d4', '#fbcfe8']} {...props} />,
  trendingUp: (props) => <TrendingUp theme="multi-color" fill={['#f59e0b', '#fbbf24', '#fcd34d', '#fde68a']} {...props} />,
  bug: (props) => <Bug theme="multi-color" fill={['#ef4444', '#f87171', '#fca5a5', '#fecaca']} {...props} />,
  comments: (props) => <Comments theme="multi-color" fill={['#06b6d4', '#22d3ee', '#67e8f9', '#a5f3fc']} {...props} />,
  github: (props) => <GithubIcon theme="filled" fill={['#24292e']} {...props} />,
};

// Icon with animated gradient background
export function IconWithGradientBg({
  icon: IconComponent,
  size = 48,
  gradientColors = ['#667eea', '#764ba2'],
  className = ''
}) {
  return (
    <div
      className={`inline-flex items-center justify-center rounded-2xl p-3 shadow-lg ${className}`}
      style={{
        background: `linear-gradient(135deg, ${gradientColors.join(', ')})`,
        boxShadow: '0 8px 25px rgba(102, 126, 234, 0.3)'
      }}
    >
      {IconComponent}
    </div>
  );
}

export default ColorfulIcons;
