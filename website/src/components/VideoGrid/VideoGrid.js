import React from 'react';
import Slider from 'react-slick';
import styles from './VideoGrid.module.css';
import 'slick-carousel/slick/slick.css';
import 'slick-carousel/slick/slick-theme.css';

const videos = [
  {
    title: "AWS re:Invent 2023 - Data processing at massive scale on Amazon EKS",
    description: "Data processing at massive scale with Spark on Amazon EKS by Pinterest.",
    imageSrc: 'news/con309.png',
    linkTo: "https://www.youtube.com/watch?v=G9aNXEu_a8k",
    date: "Dec 4, 2023"
  },
  {
    title: "Containers from the Couch - Data on EKS (DoEKS)",
    description: "In this demo-focused livestream, learn how to run Spark and AI/ML workloads on Amazon EKS",
    imageSrc: 'news/video2.png',
    linkTo: "https://www.youtube.com/watch?v=6n6XBDXXPSs",
    date: "Sep 21, 2023"
  },
  {
    title: "Run Stable Diffusion on Kubernetes | Generative AI on Amazon EKS",
    description: "Run Stable Diffusion on Kubernetes | Generative AI on Amazon EKS",
    imageSrc: 'news/video6.png',
    linkTo: "https://www.youtube.com/watch?v=-41bX6AjMu4",
    date: "Aug 24, 2023"
  },
  {
    title: "AWS Summit Tel Aviv 2023 - Building a modern data platform on Amazon EKS",
    description: "AWS Summit Tel Aviv 2023 - Building a modern data platform on Amazon EKS",
    imageSrc: 'news/video4.png',
    linkTo: "https://www.youtube.com/watch?v=SS8zgvHNo38",
    date: "Jun 29, 2023"
  },
  {
    title: "Generative AI Modeling on Amazon EKS ft. Karpenter, Ray, JupyterHub and DoEKS",
    description: "Generative AI Modeling on Amazon EKS ft. Karpenter, Ray, JupyterHub and DoEKS",
    imageSrc: 'news/video5.png',
    linkTo: "https://www.youtube.com/watch?v=h1RRdYHdDiY",
    date: "Oct 5, 2023"
  },
  {
    title: "Building a Modern Data Platform on Amazon EKS - AWS Online Tech Talk",
    description: "Building a Modern Data Platform on Amazon EKS - AWS Online Tech Talk",
    imageSrc: 'news/video3.png',
    linkTo: "https://www.youtube.com/watch?v=7AHuMNqbR7o",
    date: "Feb 2, 2023"
  },
];

const VideoGrid = () => {
  const settings = {
    dots: true,
    infinite: true,
    speed: 500,
    slidesToShow: 3,
    slidesToScroll: 3,
    nextArrow: <SampleNextArrow />,
    prevArrow: <SamplePrevArrow />,
    responsive: [
      {
        breakpoint: 1024,
        settings: {
          slidesToShow: 2,
          slidesToScroll: 2,
          infinite: true,
          dots: true
        }
      },
      {
        breakpoint: 600,
        settings: {
          slidesToShow: 1,
          slidesToScroll: 1,
          initialSlide: 1
        }
      },
    ]
  };

  return (
    <div className={styles.videoGridContainer}>
      <Slider {...settings}>
        {videos.map((video, index) => (
          <div key={index} className={styles.videoCard}>
            <a href={video.linkTo} target="_blank" rel="noopener noreferrer">
              <img src={video.imageSrc} alt={video.title} className={styles.thumbnail} />
            </a>
            <div className={styles.videoInfo}>
              <h3>{video.title}</h3>
              <small>{video.date}</small>
              <p>{video.description}</p>
            </div>
          </div>
        ))}
      </Slider>
    </div>
  );
};

const SampleNextArrow = (props) => {
  const { className, style, onClick } = props;
  return (
    <div
      className={`${className} ${styles.arrow}`}
      style={{ ...style, display: 'block' }}
      onClick={onClick}
    >
      &#10095;
    </div>
  );
};

const SamplePrevArrow = (props) => {
  const { className, style, onClick } = props;
  return (
    <div
      className={`${className} ${styles.arrow}`}
      style={{ ...style, display: 'block' }}
      onClick={onClick}
    >
      &#10094;
    </div>
  );
};

export default VideoGrid;