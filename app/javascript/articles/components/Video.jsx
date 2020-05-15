import { h } from 'preact';
import { articlePropTypes } from '../../common-prop-types';

export const Video = ({ article }) => {
  return (
    <a
      href={article.path}
      className="crayons-story__video"
      style={`background-image:url(${article.cloudinary_video_url})`}
    >
      <span className="crayons-story__video__time">
        {article.video_duration_in_minutes}
      </span>
    </a>
  );
};

Video.propTypes = {
  article: articlePropTypes.isRequired,
};

Video.displayName = 'Video';
