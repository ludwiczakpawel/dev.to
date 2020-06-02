module Moderator
  class MergeUser < ManageActivityAndRoles
    def self.call(admin:, keep_user:, delete_user_id:)
      new(keep_user: keep_user, admin: admin, delete_user_id: delete_user_id).merge
    end

    attr_reader :keep_user, :admin, :delete_user_id

    def initialize(admin:, keep_user:, delete_user_id:)
      @keep_user = keep_user
      @admin = admin
      @delete_user = User.find(delete_user_id.to_i)
    end

    def merge
      raise "You cannot merge the same two user id#s" if @delete_user.id == @keep_user.id

      handle_identities
      merge_content
      merge_follows
      merge_chat_mentions
      merge_profile
      update_social
      Users::DeleteWorker.new.perform(@delete_user.id, true)
      @keep_user.touch(:profile_updated_at)
      Users::MergeSyncWorker.perform_async(@keep_user.id)

      CacheBuster.bust("/#{@keep_user.username}")
    end

    private

    def handle_identities
      raise "The user being deleted already has two identities. Are you sure this is the right user to be deleted? If so, a super admin will need to do this from the console to be safe." if @delete_user.identities.count > 1

      return true if @keep_user.identities.count > 1 || @delete_user.identities.none? || @keep_user.identities.last.provider == @delete_user.identities.last.provider

      @delete_user.identities.first.update_columns(user_id: @keep_user.id)
    end

    def update_social
      @old_tu = @delete_user.twitter_username
      @old_gu = @delete_user.github_username
      ActiveRecord::Base.transaction do
        @delete_user.update_columns(twitter_username: nil, github_username: nil)
        @keep_user.update_columns(twitter_username: @old_tu) if @keep_user.twitter_username.nil?
        @keep_user.update_columns(github_username: @old_gu) if @keep_user.github_username.nil?
        @keep_user.touch(:profile_updated_at, :last_followed_at) # clears cache on sidebar
      end
    end

    def merge_profile
      if @delete_user.github_repos.any?
        @delete_user.github_repos.update_all(user_id: @keep_user.id)
        @keep_user.touch(:github_repos_updated_at)
      end
      if @delete_user.badge_achievements.any?
        @delete_user.badge_achievements.update_all(user_id: @keep_user.id)
        BadgeAchievement.counter_culture_fix_counts(where: { users: { id: @keep_user.id } })
      end

      @keep_user.update_columns(created_at: @delete_user.created_at) if @delete_user.created_at < @keep_user.created_at
    end

    def merge_chat_mentions
      @delete_user.chat_channel_memberships.update_all(user_id: @keep_user.id) if @delete_user.chat_channel_memberships.any?
      @delete_user.mentions.update_all(user_id: @keep_user.id) if @delete_user.mentions.any?
    end

    def merge_follows
      @delete_user.follows&.update_all(follower_id: @keep_user.id) if @delete_user.follows.any?
      @delete_user_followers = Follow.followable_user(@delete_user.id)
      @delete_user_followers.update_all(followable_id: @keep_user.id) if @delete_user_followers.any?
    end

    def merge_content
      merge_reactions if @delete_user.reactions.any?
      merge_comments if @delete_user.comments.any?
      merge_articles if @delete_user.articles.any?
    end

    def merge_reactions
      @delete_user.reactions.update_all(user_id: @keep_user.id)
      @keep_user.reactions_count = @keep_user.reactions.size
    end

    def merge_comments
      @delete_user.comments.update_all(user_id: @keep_user.id)
      @keep_user.comments_count = @keep_user.comments.size
    end

    def merge_articles
      @delete_user.articles.update_all(user_id: @keep_user.id)
      @keep_user.articles_count = @keep_user.articles.size
    end
  end
end
