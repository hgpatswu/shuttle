# Copyright 2013 Square Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

class SearchController < ApplicationController
  before_filter :authenticate_user!

  def translations
    respond_to do |format|
      format.html # translations.html.rb

      format.json do
        @results = Translation.order('translations.id DESC').
            offset(params[:offset].to_i).
            limit(params.fetch(:limit, 50)).
            includes(key: [:slugs, :project])

        project_id = params[:project_id].to_i
        if project_id > 0
          @results = @results.joins(:key).where(keys: {project_id: params[:project_id]})
        end

        if params[:target_locales].present?
          @target_locales = params[:target_locales].split(',').map { |l| Locale.from_rfc5646(l.strip) }
          return head(:unprocessable_entity) unless @target_locales.all?
          @results = @results.where(rfc5646_locale: @target_locales.map(&:rfc5646))
        end

        method   = case params[:field]
                     when 'searchable_source_copy' then
                       :source_copy_query
                     else
                       :copy_query
                   end
        tsc      = @locale ? SearchableField::text_search_configuration(@locale) : 'english'
        @results = if params[:query].present?
                     @results.send(method, params[:query], tsc)
                   else
                     @results.where('FALSE')
                   end

        render json: decorate_translations(@results).to_json
      end
    end
  end

  def keys
    respond_to do |format|
      format.html # keys.html.erb
      format.json do
        return head(:unprocessable_entity) if params[:project_id].to_i <= 0

        @results = Key.by_key.
            offset(params[:offset].to_i).
            limit(params.fetch(:limit, 50)).
            includes(:translations, :project, :slugs).
            where(keys: {project_id: params[:project_id]}).
            original_key_query(params[:filter]).
            order('key_prefix ASC')

        render json: decorate_keys(@results).to_json
      end
    end
  end

  private

  def decorate_translations(translations)
    translations.map do |translation|
      translation.as_json.merge(
          locale:        translation.locale.as_json,
          source_locale: translation.source_locale.as_json,
          url:           (if current_user.translator?
                           edit_project_key_translation_url(translation.key.project, translation.key, translation)
                         else
                           project_key_translation_url(translation.key.project, translation.key, translation)
                         end),
          project:       translation.key.project.as_json
      )
    end
  end

  def decorate_keys(keys)
    keys.map do |key|
      translations = if current_user.approved_locales.empty? then
                       key.translations
                     else
                       key.translations.select { |t| current_user.approved_locales.include?(t.locale) }
                     end
      key.as_json.merge(
          translations: translations.map do |translation|
            translation.as_json.merge(
                url: if current_user.translator?
                       edit_project_key_translation_url(translation.key.project, translation.key, translation)
                     else
                       project_key_translation_url(translation.key.project, translation.key, translation)
                     end
            )
          end
      )
    end
  end
end
