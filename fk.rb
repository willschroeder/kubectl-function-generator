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

# TODO, main function, and rest of functions with param enforcement, smart tabbing, bash error catching output

require 'pp'

script = %q(
  def main() {
    $NS="benjamins-release"
    $POD="benjamins-release"
    bash_into($POD, $NS)
  }
)

Token = Struct.new(:type, :value)

class Tokenizer
  TOKEN_TYPES = [
      [:func_def, /\bdef\b/],
      [:var, /\$[A-Z]+/,/[A-Z]+/],
      [:string, /"(.*?)"/, /\b[a-zA-Z-]+\b/],
      [:identifier, /\b[a-zA-Z_]+\b/],
      [:oparen, /\(/],
      [:cparen, /\)/],
      [:comma, /,/],
      [:equal, /=/],
      [:openb, /{/],
      [:closeb, /}/]
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

DefNode = Struct.new(:name, :arg_names, :body)
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
    parse_func_def
  end

  def parse_func_def
    consume(:func_def)
    name = consume(:identifier).value
    args = parse_func_def_args
    body = parse_func_def_body
    DefNode.new(name, args, body)
  end

  def parse_func_def_args
    consume(:oparen)

    if peek(:cparen)
      consume(:cparen)
      return []
    end

    args = []
    args << consume(:identifier).value
    while peek(:comma)
      consume(:comma)
      args << consume(:identifier).value
    end
    consume(:cparen)

    args
  end

  def parse_func_def_body
    consume(:openb)
    expressions = []

    until peek(:closeb)
      expressions << parse_expression
    end

    expressions
  end

  def parse_var_set
    name = consume(:var).value
    consume(:equal)

    if @vars.include?(name)
      raise "Already have defined variable #{name}"
    end
    @vars << name

    value = parse_string

    VarSetNode.new(name, value)
  end

  def parse_var_get
    value = consume(:var).value

    unless @vars.include?(value)
      raise "A variable named #{value} has not been set"
    end

    VarGetNode.new(value)
  end

  def parse_string
    StringNode.new(consume(:string).value)
  end

  def parse_call
    name = consume(:identifier).value
    args = parse_call_args
    CallNode.new(name, args)
  end

  def parse_call_args
    consume(:oparen)

    if peek(:cparen)
      return []
    end

    expressions = []
    expressions << parse_expression
    while peek(:comma)
      consume(:comma)
      expressions << parse_expression
    end
    consume(:cparen)

    expressions
  end

  def parse_expression
    if peek(:string)
      parse_string
    elsif peek(:identifier) && peek(:oparen, 1)
      parse_call
    elsif peek(:var) && peek(:equal,1)
      parse_var_set
    elsif peek(:var)
      parse_var_get
    else
      raise "Unknown expression #{@tokens[0]}"
    end
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

KNOWN_FUNCTIONS = {
    ask: {
        required: 1,
        optional: 1
    },
    find_namespace: {
        required: 1,
        optional: 0
    },
    find_pod: {
        required: 1,
        optional: 0
    },
    scale_pods_in_namespace_to: {
        required: 2,
        optional: 0
    },
    bash_into: {
        required: 1,
        optional: 1
    },
    tail_log: {
        required: 1,
        optional: 1
    },
    port_forward: {
        required: 3,
        optional: 1
    }
}

class Generator
  def initialize(root)
    @root = root
  end

  def generate
    gen(@root)
  end

  def gen(node)
    case node
    when DefNode
      "function #{node.name}(#{node.arg_names.join(',')}) {\n" + node.body.map{|i| gen(i)}.join("\n") + "\n}"
    when VarSetNode
      "#{node.name}=#{gen(node.value)}"
    when VarGetNode
      "$#{node.name}"
    when StringNode
      node.value
    when CallNode
      case node.name
      when "bash_into"
        func_validate("bash_into", node.args.count, 1,1)
        ns = ""
        if node.args[1]
          ns = "-n #{gen(node.args[1])} "
        end
        "kubectl exec #{ns}-it #{gen(node.args[0])} -- /bin/bash"
      else
        raise "Unknown function, cant call #{node.name}"
      end
    else
      raise "Unsure what to do with #{node}"
    end
  end

  def func_validate(name, args_count, required, optional)
    if args_count < required
      raise "Expecting at least #{min} args but got #{args_count} for #{name}"
    elsif args_count > required + optional
      raise "Got #{args_count} args for #{name} but the maximum is #{required + optional}"
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