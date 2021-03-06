require_dependency 'oneboxer/oembed_onebox'
require_dependency 'freedom_patches/rails4'

module Oneboxer
  class DiscourseOnebox < BaseOnebox
    include ActionView::Helpers::DateHelper

    matcher do
      Regexp.new "^#{Discourse.base_url.gsub(".","\\.")}.*$", true
    end

    def onebox
      uri = URI::parse(@url)
      route = Rails.application.routes.recognize_path(uri.path)

      args = {original_url: @url}

      # Figure out what kind of onebox to show based on the URL
      case route[:controller]
      when 'users'
        user = User.where(username_lower: route[:username].downcase).first
        Guardian.new.ensure_can_see!(user)

        args.merge! avatar: PrettyText.avatar_img(user.username, 'tiny'), username: user.username
        args[:bio] = user.bio_cooked if user.bio_cooked.present?

        @template = 'user'
      when 'topics'
        if route[:post_number].present? && route[:post_number].to_i > 1
          # Post Link
          post = Post.where(topic_id: route[:topic_id], post_number: route[:post_number].to_i).first
          Guardian.new.ensure_can_see!(post)

          topic = post.topic
          slug = Slug.for(topic.title)

          excerpt = post.excerpt(SiteSetting.post_onebox_maxlength)
          excerpt.gsub!("\n"," ")
          # hack to make it render for now
          excerpt.gsub!("[/quote]", "[quote]")
          quote = "[quote=\"#{post.user.username}, topic:#{topic.id}, slug:#{slug}, post:#{post.post_number}\"]#{excerpt}[/quote]"

          cooked = PrettyText.cook(quote)
          return cooked

        else
          # Topic Link
          topic = Topic.where(id: route[:topic_id].to_i).includes(:user).first
          post = topic.posts.first
          Guardian.new(nil).ensure_can_see!(topic)

          posters = topic.posters_summary.map do |p|
            {username: p[:user][:username],
             avatar: PrettyText.avatar_img(p[:user][:username], 'tiny'),
             description: p[:description],
             extras: p[:extras]}
          end

          category = topic.category
          if category
            category = "<a href=\"/category/#{category.name}\" class=\"badge badge-category\" style=\"background-color: ##{category.color}\">#{category.name}</a>"
          end

          quote = post.excerpt(SiteSetting.post_onebox_maxlength)
          args.merge! title: topic.title,
                      avatar: PrettyText.avatar_img(topic.user.username, 'tiny'),
                      posts_count: topic.posts_count,
                      last_post: FreedomPatches::Rails4.time_ago_in_words(topic.last_posted_at, false, scope: :'datetime.distance_in_words_verbose'),
                      age: FreedomPatches::Rails4.time_ago_in_words(topic.created_at, false, scope: :'datetime.distance_in_words_verbose'),
                      views: topic.views,
                      posters: posters,
                      quote: quote,
                      category: category,
                      topic: topic.id

          @template = 'topic'
        end

      end

      return nil unless @template
      Mustache.render(File.read("#{Rails.root}/lib/oneboxer/templates/discourse_#{@template}_onebox.hbrs"), args)
    rescue ActionController::RoutingError
      nil
    end

  end
end
