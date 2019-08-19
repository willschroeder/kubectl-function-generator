#!/usr/bin/env ruby

# parse_namespace https://syntagmatic-foreign-policy.dqa.life/; scale_pods 1; find_pod_including main-site; bash_into;
# set_namespace benjamins-release; find_pod_including benjamins-release; tail_log;
#
# $VAR="value" # all variables are all caps, start with $, must be strings, and are global
# $OUT=ask("contextual question", regex?)
# $NS=find_namespace(namespace) # fuzzy
# $POD=find_pod(pod) # fuzzy
# scale_pods_in_namespace_to(namespace, count)
# bash_into(pod, namespace?)
# tail_log(pod, namespace?)
# port_forward(pod, local, remote, namespace?)
#
# https://github.com/walerian777/destroy-all-software/tree/master/compiler

# TODO, variable use checking, main function, and rest of functions, smart tabbing

require 'pp'

script = %q(
  $NS="benjamins-release"
  $POD="benjamins-release"
  bash_into($POD, $NS)
)

Token = Struct.new(:type, :value)

class Tokenizer
  TOKEN_TYPES = [
      [:var, /\$[A-Z]+/,/[A-Z]+/],
      [:string, /"(.*?)"/, /\b[a-zA-Z-]+\b/],
      [:identifier, /\b[a-zA-Z_]+\b/],
      [:oparen, /\(/],
      [:cparen, /\)/],
      [:comma, /,/],
      [:equal, /=/],
  ].freeze

  def initialize(code)
    @code = code.strip.gsub("\n"," ")
  end

  def tokenize
    tokens = []
    until @code.empty?
      tokens << tokenize_one_token
      @code = @code.strip
    end
    tokens
  end

  def tokenize_one_token
    TOKEN_TYPES.each do |(type, find, extract)|
      # restrict to beginning of string
      find = /\A(#{find})/
      find_matches = find.match(@code)
      next unless find_matches && find_matches.length > 0
      find_match = find_matches[0]

      # if no extract, then the find value is alright
      if extract.nil?
        value = find_match
      else
        extract_matches = find_match.match(extract)
        raise "Extract unable to lift from #{find_match}" unless extract_matches && extract_matches.length > 0
        value = extract_matches[0]
      end

      @code = @code[find_match.length..-1]
      return Token.new(type, value)
    end

    raise "Couldn't match token on #{@code.inspect}"
  end
end

RootNode = Struct.new(:body)
CallNode = Struct.new(:name, :args)
VarSetNode = Struct.new(:name, :value)
VarGetNode = Struct.new(:name)
StringNode = Struct.new(:value)

class Parser
  def initialize(tokens)
    @tokens = tokens
    @vars = []
  end

  def parse
    root = RootNode.new([])
    while @tokens.any?
      if peek(:var) and peek(:equal, 1)
        root.body << set_var
      elsif peek(:identifier) and peek(:oparen, 1)
        root.body << parse_call
      else
        raise "Unsure what to do with #{@tokens.first} at root"
      end
    end
    root
  end

  def set_var
    name = consume(:var).value
    consume(:equal)

    if @vars.include?(name)
      raise "Already have defined variable #{name}"
    end
    @vars << name
    
    value = parse_string

    VarSetNode.new(name, value)
  end
  
  def parse_string
    StringNode.new(consume(:string).value)
  end

  def parse_call
    name = consume(:identifier).value
    args = parse_arg_exprs
    CallNode.new(name, args)
  end

  def parse_arg_exprs
    consume(:oparen)

    if peek(:cparen)
      return []
    end

    arg_exprs = []
    arg_exprs << parse_argument
    while peek(:comma)
      consume(:comma)
      arg_exprs << parse_argument
    end
    consume(:cparen)

    arg_exprs
  end

  def parse_argument
    if peek(:string)
      parse_string 
    elsif peek(:identifier) && peek(:oparen, 1)
      parse_call
    else
      parse_var_get
    end
  end

  def parse_var_get
    VarGetNode.new(consume(:var).value)
  end

  def consume(expected_type)
    token = @tokens.shift
    return token if token.type == expected_type

    raise "Expected token type #{expected_type.inspect} but got #{token.type.inspect}"
  end

  def peek(expected_type, offset = 0)
    @tokens.fetch(offset).type == expected_type
  end
end

KNOWN_FUNCTIONS = %w(ask find_namespace find_pod scale_pods_in_namespace_to bash_into tail_log port_forward)

class Generator
  def initialize(root)
    @root = root
    @output = []
  end

  def generate
    @root.body.each do |expr|
      @output << "\t" + gen(expr)
    end

    @output.unshift("function krun() {")
    @output.append("}")
    @output.join("\n")
  end

  def gen(node)
    case node
    when VarSetNode
      "#{node.name}=#{gen(node.value)}"
    when VarGetNode
      "$#{node.name}"
    when StringNode
      node.value
    when CallNode
      case node.name
      when "bash_into"
        ns = ""
        if node.args[1]
          ns = "-n #{gen(node.args[1])} "
        end
        "kubectl exec #{ns}-it #{gen(node.args[0])} -- /bin/bash"
      end
    else
      raise "Unsure what to do with #{node}"
    end
  end
end

tokens = Tokenizer.new(script).tokenize
pp tokens
parse_tree = Parser.new(tokens).parse
pp parse_tree
func = Generator.new(parse_tree).generate
puts func


# function dqar() {
#   if [ "$1" == "" ]; then
#     echo "What is the DQA url?"
#     read url
#   else
#     url="$1"
#     fi
#
#     DQA=`ruby -e "url=\"$url\"; puts url[8.. url.length-1].split('.').first"`
#     echo "DQA: $DQA"
#     export DQA
#
#     k_ns=`kubectl get ns | grep $DQA`
#     NS=`ruby -e "puts \"$k_ns\".split(' ').first"`
#     echo "NS: $NS"
#     export NS
#
#     echo "Scaling all pods to 1 per type"
#     k_scale=`kubectl scale deploy -n $NS --replicas=1 --all`
#
#     echo "Select pod type"
#     echo "1) main-site"
#     read choice
#     case $choice in
#     "1")
#       pod_short="main-site"
#       ;;
#       esac
#
#       k_pod=`kubectl -n $NS get pods | grep $pod_short | grep Running`
#       POD=`ruby -e "puts \"$k_pod\".split(' ').first"`
#       echo "POD: $POD"
#       export POD
#
#       echo "1) Bash"
#       echo "2) Tail Log"
#       echo "3) Exit w/ Values"
#       read choice
#       case $choice in
#       "1")
#         kubectl -n $NS exec -it $POD -- /bin/bash
#         ;;
#         "2")
#         kubectl -n $NS logs $POD -f
#         ;;
#         "3")
#         ;;
#         esac
#         }