#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Domgen
  module Generator
    module JMX
      TEMPLATE_DIRECTORY = "#{File.dirname(__FILE__)}/templates"
      FACETS = [:jmx]
      HELPERS = [Domgen::Java::Helper]
    end
  end
end
Domgen.template_set(:jmx) do |template_set|
  template_set.template(Domgen::Generator::JMX::FACETS,
                        :service,
                        "#{Domgen::Generator::JMX::TEMPLATE_DIRECTORY}/service.java.erb",
                        'main/java/#{service.jmx.qualified_service_name.gsub(".","/")}.java',
                        Domgen::Generator::JMX::HELPERS)
end
