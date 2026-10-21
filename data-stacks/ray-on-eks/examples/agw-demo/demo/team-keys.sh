# Load the three team API keys into your current shell (zsh or bash), without
# printing them:   source demo/team-keys.sh
export KUBECONFIG="${KUBECONFIG:-$HOME/Documents/github/data-on-eks/data-stacks/ray-on-eks/kubeconfig.yaml}"
_agw_key() { kubectl -n agw-demo get secret agw-demo-team-keys -o "jsonpath={.data.$1}" | base64 -d; }
export SEARCH_KEY="$(_agw_key TEAM_SEARCH_KEY)"
export SUPPORT_KEY="$(_agw_key TEAM_SUPPORT_KEY)"
export LABS_KEY="$(_agw_key TEAM_LABS_KEY)"
unset -f _agw_key
echo "loaded SEARCH_KEY SUPPORT_KEY LABS_KEY (lengths: ${#SEARCH_KEY} ${#SUPPORT_KEY} ${#LABS_KEY})"
