#!/usr/bin/env ruby
#
# Check for changed posts

Jekyll::Hooks.register :posts, :post_init do |post|
  # Docker production builds intentionally exclude .git. Keep the feature for
  # checked-out source trees, but do not make static builds depend on VCS data.
  in_git_worktree = system(
    'git', 'rev-parse', '--is-inside-work-tree',
    out: File::NULL,
    err: File::NULL
  )
  next unless in_git_worktree

  commit_num = `git rev-list --count HEAD "#{ post.path }"`

  if commit_num.to_i > 1
    lastmod_date = `git log -1 --pretty="%ad" --date=iso "#{ post.path }"`
    post.data['last_modified_at'] = lastmod_date
  end

end
