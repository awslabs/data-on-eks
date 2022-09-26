// @ts-check
// Note: type annotations allow type checking and IDEs autocompletion

const lightCodeTheme = require('prism-react-renderer/themes/github');
const darkCodeTheme = require('prism-react-renderer/themes/dracula');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Data on EKS (DoEKS)',
  tagline: 'Accelerate your Data journey on Amazon EKS',
  url: 'https://awslabs.github.io',
  baseUrl: '/',
  trailingSlash: false,
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  // favicon: 'img/favicon.ico',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'awslabs', // Usually your GitHub org/user name.
  projectName: 'data-on-eks', // Usually your repo name.
  // deploymentBranch: 'main',
  githubHost: 'github.com',
  // Even if you don't use internalization, you can use this field to set useful
  // metadata like html lang. For example, if your site is Chinese, you may want
  // to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: require.resolve('./sidebars.js'),
          // Please change this to your repo.
          // Remove this to remove the "edit this page" links.
          editUrl:
            'https://github.com/awslabs/data-on-eks/blob/main/website/docs/',
        },
        blog: {
          blogSidebarTitle: 'All posts',
          blogSidebarCount: 'ALL',
          showReadingTime: true,
          // Please change this to your repo.
          // Remove this to remove the "edit this page" links.
          editUrl:
              'https://github.com/awslabs/data-on-eks/blob/main/website/blog/',
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: 'DoEKS',
        // logo: {
        //   alt: 'DoEKS Logo',
        //   src: 'img/logo.svg',
        // },
        items: [
          {
            type: 'doc',
            docId: 'intro',
            position: 'left',
            label: 'Welcome',
          },
          {
            type: 'doc',
            docId: 'amazon-emr-on-eks/index',
            position: 'left',
            label: 'EMR on EKS',
          },
          {
            type: 'doc',
            docId: 'spark-on-eks/index',
            position: 'left',
            label: 'Spark on EKS',
          },
          {
            type: 'doc',
            docId: 'ai-ml-eks/index',
            position: 'left',
            label: 'AI/ML',
          },
          {
            type: 'doc',
            docId: 'distributed-databases-eks/index',
            position: 'left',
            label: 'Distributed Databases',
          },
          {
            type: 'doc',
            docId: 'streaming-platforms-eks/index',
            position: 'left',
            label: 'Streaming Platforms',
          },
          {
            type: 'doc',
            docId: 'job-schedulers-eks/index',
            position: 'left',
            label: 'Job Schedulers',
          },
          {to: '/blog', label: 'Blog', position: 'left'},
          {
            href: 'https://github.com/awslabs/data-on-eks',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Get Started',
            items: [
              {
                label: 'Docs',
                to: '/docs/intro',
              },
            ],
          },
          {
            title: 'Get Involved',
            items: [
              {
                label: 'Github',
                href: 'https://github.com/awslabs/data-on-eks',
              }
            ],
          },
          {
            title: 'More',
            items: [
              {
                label: 'Blog',
                to: '/blog',
              }
            ],
          },
        ],
        copyright: `Built with ❤️ at AWS  <br/> © ${new Date().getFullYear()} Amazon.com, Inc. or its affiliates. All Rights Reserved`,
      },
      prism: {
        theme: lightCodeTheme,
        darkTheme: darkCodeTheme,
      },
    }),
 // TODO Search plugin not working. Fix this
 //  plugins: [
 //    // ...
 //    '@aldridged/docusaurus-plugin-lunr'
 //  ],
};

module.exports = config;
