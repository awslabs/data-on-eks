# Navbar Size Adjustment Guide

## Current Settings (Optimized for Better Visibility)

All navbar sizing is controlled by CSS variables in `/website/src/css/custom.css` (lines 19-24):

```css
/* Custom navbar sizing variables - easy to adjust */
--navbar-item-font-size: 17px;              /* Text size (was 16px) */
--navbar-item-padding-vertical: 10px;       /* Top/bottom padding (was 12px) */
--navbar-item-padding-horizontal: 20px;     /* Left/right padding (was 16px) */
--navbar-icon-size: 20px;                   /* Icon width/height (was 18px) */
--navbar-icon-margin: 10px;                 /* Space between icon and text (was 8px) */
```

## How to Adjust Sizes

### To Make Items LARGER:
```css
--navbar-item-font-size: 18px;              /* Larger text */
--navbar-item-padding-vertical: 12px;       /* More vertical space */
--navbar-item-padding-horizontal: 24px;     /* More horizontal space */
--navbar-icon-size: 22px;                   /* Bigger icons */
--navbar-icon-margin: 12px;                 /* More icon spacing */
```

### To Make Items SMALLER (Rollback):
```css
--navbar-item-font-size: 16px;              /* Original size */
--navbar-item-padding-vertical: 8px;        /* Less vertical space */
--navbar-item-padding-horizontal: 16px;     /* Original horizontal space */
--navbar-icon-size: 18px;                   /* Original icon size */
--navbar-icon-margin: 8px;                  /* Original icon spacing */
```

### Recommended Size Presets

#### Conservative (Subtle Increase)
```css
--navbar-item-font-size: 16.5px;
--navbar-item-padding-vertical: 10px;
--navbar-item-padding-horizontal: 18px;
--navbar-icon-size: 19px;
--navbar-icon-margin: 9px;
```

#### Balanced (Current - Good for Most Users)
```css
--navbar-item-font-size: 17px;
--navbar-item-padding-vertical: 10px;
--navbar-item-padding-horizontal: 20px;
--navbar-icon-size: 20px;
--navbar-icon-margin: 10px;
```

#### Bold (Maximum Visibility)
```css
--navbar-item-font-size: 18px;
--navbar-item-padding-vertical: 12px;
--navbar-item-padding-horizontal: 24px;
--navbar-icon-size: 22px;
--navbar-icon-margin: 12px;
```

## Navbar Height

The navbar height is also adjustable (lines 13 and 33 in custom.css):

```css
:root {
  --ifm-navbar-height: 5rem;  /* Increased from 4.5rem */
}

html[data-theme="dark"] {
  --ifm-navbar-height: 5rem;  /* Increased from 4.5rem */
}
```

### Height Presets:
- **Compact**: `4.5rem` (original)
- **Balanced**: `5rem` (current)
- **Spacious**: `5.5rem`

## Testing Changes

After editing `/website/src/css/custom.css`:

1. Save the file
2. Rebuild: `npm run build`
3. View in browser
4. If too big/small, adjust variables and rebuild

## Quick Rollback

To restore original bookmark-like size, set all variables to these values:
```css
--navbar-item-font-size: 16px;
--navbar-item-padding-vertical: 12px;
--navbar-item-padding-horizontal: 16px;
--navbar-icon-size: 18px;
--navbar-icon-margin: 8px;
--ifm-navbar-height: 4.5rem;
```
