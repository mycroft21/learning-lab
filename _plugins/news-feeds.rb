# frozen_string_literal: true

# 빌드 시점에 뉴스 피드를 받아 site.data['news_feeds'] 에 채운다.
#
# 브라우저에서 직접 받을 수 없어서(두 피드 모두 CORS 헤더를 주지 않는다) 빌드 때
# 가져와 HTML 에 박는다. 그래서 신선도는 빌드 주기에 묶인다 — 워크플로의 schedule 을
# 참고. 실패는 절대 빌드를 깨지 않는다. 못 가져오면 items 가 비고, 위젯은 헤드라인
# 없이 소스 링크만 보여준다.
#
# 로컬에서 파싱을 검증할 때는 네트워크 대신 파일을 읽게 할 수 있다:
#   NEWS_FEEDS_FIXTURES=test/fixtures bundle exec jekyll b
# 이러면 <dir>/<slug>.xml 을 읽는다.

require 'net/http'
require 'rexml/document'
require 'uri'

module NewsFeeds
  SOURCES = [
    { 'slug' => 'geeknews', 'name' => 'GeekNews',
      'site' => 'https://news.hada.io/', 'feed' => 'https://news.hada.io/rss/news' },
    { 'slug' => 'hackernews', 'name' => 'Hacker News',
      'site' => 'https://news.ycombinator.com/', 'feed' => 'https://news.ycombinator.com/rss' }
  ].freeze

  PER_SOURCE = 3
  TIMEOUT = 5
  MAX_REDIRECTS = 2

  class Generator < Jekyll::Generator
    priority :high

    def generate(site)
      site.data['news_feeds'] = SOURCES.map do |src|
        src.merge('items' => items_for(src))
      end
    end

    private

    def items_for(src)
      xml = read_feed(src)
      return [] if xml.nil? || xml.empty?

      parse(xml)
    rescue StandardError => e
      warn_once(src['feed'], "파싱 실패 — #{e.class}: #{e.message}")
      []
    end

    def read_feed(src)
      dir = ENV['NEWS_FEEDS_FIXTURES']
      if dir && !dir.empty?
        path = File.join(dir, "#{src['slug']}.xml")
        return File.exist?(path) ? File.read(path, encoding: 'UTF-8') : nil
      end

      fetch(src['feed'])
    end

    def fetch(url, redirects = 0)
      uri = URI.parse(url)
      return nil unless %w[http https].include?(uri.scheme)

      res = Net::HTTP.start(uri.host, uri.port,
                            use_ssl: uri.scheme == 'https',
                            open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'learning-lab-site (+https://mycroft21.github.io/learning-lab/)')
      end

      case res
      when Net::HTTPSuccess
        res.body.force_encoding('UTF-8')
      when Net::HTTPRedirection
        return nil if redirects >= MAX_REDIRECTS

        fetch(URI.join(url, res['location']).to_s, redirects + 1)
      else
        warn_once(url, "HTTP #{res.code}")
        nil
      end
    rescue StandardError => e
      # 타임아웃·DNS·TLS 등 무엇이든 빌드를 깨뜨리지 않는다.
      warn_once(url, "가져오기 실패 — #{e.class}: #{e.message}")
      nil
    end

    # RSS 2.0 의 <item>, Atom 의 <entry> 둘 다 받는다.
    def parse(xml)
      doc = REXML::Document.new(xml)
      nodes = REXML::XPath.match(doc, '//item')
      nodes = REXML::XPath.match(doc, '//entry') if nodes.empty?

      nodes.first(PER_SOURCE).filter_map do |node|
        title = text_of(node, 'title')
        url = link_of(node)
        next if title.empty? || url.nil?

        { 'title' => title, 'url' => url }
      end
    end

    def text_of(node, name)
      el = node.elements[name]
      return '' if el.nil?

      # CDATA 도 Text 의 하위라 texts 로 한 번에 모인다.
      el.texts.map(&:value).join.strip
    end

    def link_of(node)
      raw = text_of(node, 'link')
      raw = node.elements['link']&.attributes&.[]('href').to_s.strip if raw.empty?
      safe_url(raw)
    end

    # javascript: 같은 스킴이 피드에서 흘러들어오지 않게 막는다.
    def safe_url(raw)
      return nil if raw.nil? || raw.empty?

      uri = URI.parse(raw)
      %w[http https].include?(uri.scheme) ? uri.to_s : nil
    rescue URI::InvalidURIError
      nil
    end

    def warn_once(url, message)
      Jekyll.logger.warn 'NewsFeeds:', "#{url} — #{message}"
    end
  end
end
