# DataStack Tiles - Developer Guide

This guide helps developers add new tiles to DataStack pages without knowing CSS.

## 🎯 Quick Start

### 1. Import the CSS
Add this line at the top of your markdown file:
```markdown
import '@site/src/css/datastack-tiles.css';
```

### 2. Use the Grid Container
Wrap your tiles in the grid container:
```html
<div className="datastacks-grid">
  <!-- Your tiles go here -->
</div>
```

## 📋 Tile Templates

### Basic DataStack Tile (Main Index Page)
Copy and customize this template:

```html
<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">🚀</div>
<div className="datastack-content">
<h3>Your Service Name</h3>
<p className="datastack-description">Brief description of what this service does and its main benefits.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Feature 1</span>
<span className="feature-tag">Feature 2</span>
<span className="feature-tag">Feature 3</span>
<span className="feature-tag">Feature 4</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/your-service/" className="datastack-link">
<span>Explore Service</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>
```

### Example Showcase Tile (Individual Service Pages)
Copy and customize this template:

```html
<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">💾</div>
<div className="showcase-content">
<h3>Example Title</h3>
<p className="showcase-description">Detailed description of this specific example or use case.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag storage">Storage</span>
<span className="tag performance">Performance</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/service/example/" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>
```

### Featured Tile (Special Highlighting)
Add `featured` class for special emphasis:

```html
<div className="showcase-card featured">
<!-- Same content as above -->
</div>
```

## 🎨 Tag Color System

Tags automatically get colors based on their position or class name:

### Automatic Colors (by position):
- **1st tag**: Purple gradient
- **2nd tag**: Pink gradient
- **3rd tag**: Blue gradient
- **4th tag**: Green gradient

### Named Colors (by class):
- `tag infrastructure` - Purple
- `tag storage` - Pink
- `tag performance` - Blue
- `tag optimization` - Green
- `tag guide` - Orange-Pink

## 🎯 What to Customize

### ✅ Easy to Change (No CSS knowledge needed):
- **Icon**: Change the emoji (🚀, 💾, ⚡, 🌊, etc.)
- **Title**: Update the `<h3>` text
- **Description**: Update the paragraph text
- **Features/Tags**: Change the `<span>` text content
- **Links**: Update `href` attributes
- **Button Text**: Change the `<span>` inside the link

### ❌ Don't Change:
- CSS class names
- HTML structure
- SVG arrow code

## 📱 Responsive Behavior

The system automatically handles:
- **Desktop**: 2 tiles per row
- **Tablet**: 2 tiles per row
- **Mobile**: 1 tile per row

## 🎯 Example Usage

See these files for complete examples:
- `website/docs/datastacks/index.md` - Main overview page
- `website/docs/datastacks/spark-on-eks/index.md` - Individual service page

## 🔧 Need Custom Colors?

If you need different tag colors, add them to the CSS file:

```css
.tag.your-custom-name {
  background: linear-gradient(135deg, #your-color1 0%, #your-color2 100%);
  color: white;
  border-color: transparent;
}
```

Then use: `<span className="tag your-custom-name">Your Tag</span>`
